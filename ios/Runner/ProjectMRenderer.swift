import Flutter
import OpenGLES
import Accelerate
import AVFoundation

// OpenGL ES BGRA extension constant
let GL_BGRA_EXT = GLenum(0x80E1)

/// Renders projectM visualizations using OpenGL ES 3.0 and shares frames
/// with Flutter via TextureRegistry (CVPixelBuffer-backed).
class ProjectMRenderer: NSObject, FlutterTexture {
    private var registrar: FlutterTextureRegistry?
    private var textureId: Int64 = -1
    private var width: Int = 720
    private var height: Int = 480

    // OpenGL ES
    private var eaglContext: EAGLContext?
    private var framebuffer: GLuint = 0
    private var depthRenderbuffer: GLuint = 0
    private var glTexture: GLuint = 0

    // CVPixelBuffer for Flutter texture sharing
    private var pixelBuffer: CVPixelBuffer?
    private var textureCache: CVOpenGLESTextureCache?
    private var cvTexture: CVOpenGLESTexture?
    private var useFallbackReadback = false

    // projectM handle
    private var pmHandle: OpaquePointer?

    // Render loop
    private var renderThread: Thread?
    private var rendering = false
    private var targetFps: Int = 24

    // Pending preset load (queued from non-GL thread, applied on GL thread)
    private var pendingPresetPath: String?
    private let presetLock = NSLock()

    // Presets
    private var presetPaths: [String] = []
    private var currentPresetIndex: Int = 0

    // MARK: - Public API

    func initialize(registrar: FlutterTextureRegistry, width: Int, height: Int) -> Int64? {
        self.registrar = registrar
        self.width = width
        self.height = height

        // Create OpenGL ES 3.0 context (fall back to 2.0 on simulator)
        var context = EAGLContext(api: .openGLES3)
        if context == nil {
            print("ProjectM: GLES3 unavailable, trying GLES2")
            context = EAGLContext(api: .openGLES2)
        }
        guard let glContext = context else {
            print("ProjectM: Failed to create any EAGL context")
            return nil
        }
        eaglContext = glContext
        print("ProjectM: EAGL context created (API: \(glContext.api.rawValue))")

        // Set up on GL thread
        EAGLContext.setCurrent(glContext)

        // Create CVOpenGLESTextureCache for sharing with Flutter
        var cache: CVOpenGLESTextureCache?
        let cacheResult = CVOpenGLESTextureCacheCreate(
            kCFAllocatorDefault, nil,
            glContext, nil, &cache
        )
        guard cacheResult == kCVReturnSuccess, let textureCache = cache else {
            print("ProjectM: Failed to create texture cache")
            return nil
        }
        self.textureCache = textureCache

        // Create CVPixelBuffer backed by IOSurface for GPU-CPU zero-copy sharing
        let pbAttrs: NSDictionary = [
            kCVPixelBufferOpenGLESCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: NSDictionary(),
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
        ]
        var pbPool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, pbAttrs, &pbPool)

        var pb: CVPixelBuffer?
        if let pool = pbPool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb)
        }
        // Fallback: direct create if pool fails
        if pb == nil {
            CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                kCVPixelFormatType_32BGRA, pbAttrs, &pb)
        }
        guard let pixelBuffer = pb else {
            print("ProjectM: Failed to create pixel buffer")
            return nil
        }
        self.pixelBuffer = pixelBuffer
        print("ProjectM: PixelBuffer created \(width)x\(height)")

        // Try to create a GL texture backed by the CVPixelBuffer (zero-copy path)
        var cvTex: CVOpenGLESTexture?
        let texStatus = CVOpenGLESTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            GLenum(GL_TEXTURE_2D),
            GLint(GL_RGBA),
            GLsizei(width),
            GLsizei(height),
            GL_BGRA_EXT,
            GLenum(GL_UNSIGNED_BYTE),
            0,
            &cvTex
        )
        if texStatus == kCVReturnSuccess, let texture = cvTex {
            self.cvTexture = texture
            glTexture = CVOpenGLESTextureGetName(texture)
            // Configure texture sampling
            glBindTexture(GLenum(GL_TEXTURE_2D), glTexture)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
            print("ProjectM: CV texture zero-copy (GL id: \(glTexture))")
        } else {
            print("ProjectM: CV texture failed (\(texStatus)), using glReadPixels fallback")
            glGenTextures(1, &glTexture)
            glBindTexture(GLenum(GL_TEXTURE_2D), glTexture)
            glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA,
                         GLsizei(width), GLsizei(height), 0,
                         GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
            useFallbackReadback = true
        }

        // Set up framebuffer with color + depth attachments
        glGenFramebuffers(1, &framebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                               GLenum(GL_TEXTURE_2D), glTexture, 0)

        // Depth buffer — required by projectM for 3D mesh rendering
        glGenRenderbuffers(1, &depthRenderbuffer)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), depthRenderbuffer)
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER), GLenum(GL_DEPTH_COMPONENT16),
                              GLsizei(width), GLsizei(height))
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_DEPTH_ATTACHMENT),
                                  GLenum(GL_RENDERBUFFER), depthRenderbuffer)

        let fbStatus = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if fbStatus != GLenum(GL_FRAMEBUFFER_COMPLETE) {
            print("ProjectM: Framebuffer incomplete: \(fbStatus)")
            return nil
        }
        print("ProjectM: Framebuffer complete (\(width)x\(height), fallback=\(useFallbackReadback))")

        // When using CPU readback, cap FPS to avoid overload
        if useFallbackReadback {
            targetFps = min(targetFps, 24)
        }

        // Create projectM instance — must be called with GL context current and FBO bound
        pmHandle = projectm_create()
        if pmHandle == nil {
            print("ProjectM: projectm_create() returned nil — check GL errors")
            let err = glGetError()
            if err != GLenum(GL_NO_ERROR) {
                print("ProjectM: GL error after create: \(err)")
            }
            // Still extract presets even if GL fails
            extractPresets()
            EAGLContext.setCurrent(nil)
            return nil
        }
        print("ProjectM: projectm_create() succeeded")
        projectm_set_window_size(pmHandle, width, height)

        // Extract presets
        extractPresets()

        // Register Flutter texture
        textureId = registrar.register(self)

        EAGLContext.setCurrent(nil)

        return textureId
    }

    func start() {
        guard !rendering, pmHandle != nil else { return }
        rendering = true
        renderThread = Thread(target: self, selector: #selector(renderLoop), object: nil)
        renderThread?.name = "projectm-gl"
        renderThread?.qualityOfService = .userInteractive
        renderThread?.start()
    }

    func stop() {
        rendering = false
        // Wait for the render thread to actually exit
        while renderThread?.isExecuting == true {
            Thread.sleep(forTimeInterval: 0.01)
        }
        renderThread = nil
    }

    func release() {
        stop()

        if let ctx = eaglContext {
            EAGLContext.setCurrent(ctx)
        }

        if let handle = pmHandle {
            projectm_destroy(handle)
            pmHandle = nil
        }

        if framebuffer != 0 {
            glDeleteFramebuffers(1, &framebuffer)
            framebuffer = 0
        }
        if depthRenderbuffer != 0 {
            glDeleteRenderbuffers(1, &depthRenderbuffer)
            depthRenderbuffer = 0
        }
        if glTexture != 0 && useFallbackReadback {
            glDeleteTextures(1, &glTexture)
            glTexture = 0
        }

        cvTexture = nil
        pixelBuffer = nil

        if let cache = textureCache {
            CVOpenGLESTextureCacheFlush(cache, 0)
            textureCache = nil
        }

        EAGLContext.setCurrent(nil)
        eaglContext = nil

        if textureId >= 0 {
            registrar?.unregisterTexture(textureId)
            textureId = -1
        }
    }

    // MARK: - FlutterTexture

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let pb = pixelBuffer else { return nil }
        return Unmanaged.passRetained(pb)
    }

    // MARK: - Render Loop

    @objc private func renderLoop() {
        guard let ctx = eaglContext else { return }
        EAGLContext.setCurrent(ctx)

        // Temporary buffer for vertical flip when using glReadPixels fallback
        let rowBytes = width * 4
        let tempReadBuffer = useFallbackReadback
            ? UnsafeMutableRawPointer.allocate(byteCount: rowBytes * height, alignment: 16)
            : nil

        while rendering {
            autoreleasepool {
                let frameStart = CACurrentMediaTime()

                guard pmHandle != nil, framebuffer != 0 else { return }

                // Apply any pending preset load on the GL thread
                presetLock.lock()
                let pendingPath = pendingPresetPath
                pendingPresetPath = nil
                presetLock.unlock()
                if let path = pendingPath, let handle = pmHandle {
                    projectm_load_preset_file(handle, path, true)
                }

                // Bind our framebuffer
                glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
                glViewport(0, 0, GLsizei(width), GLsizei(height))

                // Feed PCM audio data from the visualization tap
                feedAudioData()

                // Render projectM frame
                if let handle = pmHandle {
                    projectm_opengl_render_frame(handle)
                }

                // If using fallback, read pixels into CVPixelBuffer and flip vertically
                if useFallbackReadback, let pb = pixelBuffer, let tmp = tempReadBuffer {
                    glFinish()
                    // Read into temp buffer (GL origin = bottom-left)
                    glReadPixels(0, 0, GLsizei(width), GLsizei(height),
                                 GL_BGRA_EXT, GLenum(GL_UNSIGNED_BYTE), tmp)

                    // Flip into CVPixelBuffer using vImage (fast SIMD)
                    CVPixelBufferLockBaseAddress(pb, [])
                    if let dest = CVPixelBufferGetBaseAddress(pb) {
                        let stride = CVPixelBufferGetBytesPerRow(pb)
                        var src = vImage_Buffer(data: tmp, height: vImagePixelCount(height),
                                                width: vImagePixelCount(width), rowBytes: rowBytes)
                        var dst = vImage_Buffer(data: dest, height: vImagePixelCount(height),
                                                width: vImagePixelCount(width), rowBytes: stride)
                        vImageVerticalReflect_ARGB8888(&src, &dst, vImage_Flags(kvImageNoFlags))
                    }
                    CVPixelBufferUnlockBaseAddress(pb, [])
                } else {
                    glFlush()
                }

                // Notify Flutter that a new frame is ready
                if rendering, textureId >= 0 {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self, self.rendering, self.textureId >= 0 else { return }
                        self.registrar?.textureFrameAvailable(self.textureId)
                    }
                }

                // Frame rate limiting
                let elapsed = CACurrentMediaTime() - frameStart
                let targetInterval = 1.0 / Double(targetFps)
                let sleepTime = targetInterval - elapsed
                if sleepTime > 0 {
                    Thread.sleep(forTimeInterval: sleepTime)
                }
            }
        }

        tempReadBuffer?.deallocate()
        EAGLContext.setCurrent(nil)
    }

    private func feedAudioData() {
        guard let handle = pmHandle else { return }
        let tap = HypeAudioTap.shared()
        guard let pcmData = tap.latestPcmFloat() else { return }

        pcmData.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
            let count = pcmData.count / MemoryLayout<Float>.size
            // Feed as mono (projectM handles mono input)
            projectm_pcm_add_float(handle, ptr, UInt32(count), PROJECTM_MONO)
        }
    }

    // MARK: - Presets

    private func extractPresets() {
        let fm = FileManager.default
        let cachePath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first!
        let presetsDir = (cachePath as NSString).appendingPathComponent("milkdrop_presets")

        // Check if already extracted
        if fm.fileExists(atPath: presetsDir) {
            loadPresetsFromDirectory(presetsDir)
            if !presetPaths.isEmpty {
                print("ProjectM: Found \(presetPaths.count) cached presets")
                return
            }
        }

        // Find Flutter asset bundle — try multiple known paths
        let candidatePaths: [String] = {
            var paths = [String]()

            // Standard: Frameworks/App.framework/flutter_assets
            if let frameworkPath = Bundle.main.privateFrameworksPath {
                let appFw = (frameworkPath as NSString).appendingPathComponent("App.framework/flutter_assets/assets/milkdrop_presets")
                paths.append(appFw)
            }

            // Direct bundle resource
            if let resPath = Bundle.main.resourcePath {
                paths.append((resPath as NSString).appendingPathComponent("flutter_assets/assets/milkdrop_presets"))
                paths.append((resPath as NSString).appendingPathComponent("Frameworks/App.framework/flutter_assets/assets/milkdrop_presets"))
            }

            // Bundle.main.path lookup
            if let faPath = Bundle.main.path(forResource: "flutter_assets", ofType: nil) {
                paths.append((faPath as NSString).appendingPathComponent("assets/milkdrop_presets"))
            }

            return paths
        }()

        var srcDir: String?
        for candidate in candidatePaths {
            if fm.fileExists(atPath: candidate) {
                srcDir = candidate
                print("ProjectM: Found presets at \(candidate)")
                break
            } else {
                print("ProjectM: Not found at \(candidate)")
            }
        }

        guard let foundDir = srcDir else {
            print("ProjectM: ERROR — Could not find milkdrop_presets in any known path")
            return
        }

        guard let files = try? fm.contentsOfDirectory(atPath: foundDir) else {
            print("ProjectM: ERROR — Could not list directory: \(foundDir)")
            return
        }
        let milkFiles = files.filter { $0.hasSuffix(".milk") }
        print("ProjectM: Found \(milkFiles.count) .milk files to extract")
        guard !milkFiles.isEmpty else { return }

        try? fm.createDirectory(atPath: presetsDir, withIntermediateDirectories: true)
        for file in milkFiles {
            let src = (foundDir as NSString).appendingPathComponent(file)
            let dst = (presetsDir as NSString).appendingPathComponent(file)
            if !fm.fileExists(atPath: dst) {
                try? fm.copyItem(atPath: src, toPath: dst)
            }
        }

        loadPresetsFromDirectory(presetsDir)
        print("ProjectM: Extracted \(presetPaths.count) presets to cache")
    }

    private func loadPresetsFromDirectory(_ dir: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        presetPaths = files
            .filter { $0.hasSuffix(".milk") }
            .sorted()
            .map { (dir as NSString).appendingPathComponent($0) }

        // Set texture search paths for projectM
        if let handle = pmHandle, !presetPaths.isEmpty {
            let dirCStr = (dir as NSString).utf8String!
            var paths: [UnsafePointer<CChar>?] = [dirCStr]
            paths.withUnsafeMutableBufferPointer { buffer in
                projectm_set_texture_search_paths(handle, buffer.baseAddress!, 1)
            }

            // Load first preset
            if let first = presetPaths.first {
                projectm_load_preset_file(handle, first, true)
            }
        }
    }

    func listPresets() -> [String] {
        return presetPaths.map { path in
            let filename = (path as NSString).lastPathComponent
                .replacingOccurrences(of: ".milk", with: "")
            // Flutter asset bundling percent-encodes filenames — decode them
            return filename.removingPercentEncoding ?? filename
        }
    }

    func loadPresetByIndex(_ index: Int) -> String {
        guard index >= 0 && index < presetPaths.count else { return "" }
        currentPresetIndex = index
        let path = presetPaths[index]

        // Queue preset load for the GL thread — projectM requires GL context
        presetLock.lock()
        pendingPresetPath = path
        presetLock.unlock()

        return decodedPresetName(path)
    }

    func nextPreset() -> String {
        guard !presetPaths.isEmpty else { return "" }
        currentPresetIndex = (currentPresetIndex + 1) % presetPaths.count
        return loadPresetByIndex(currentPresetIndex)
    }

    func previousPreset() -> String {
        guard !presetPaths.isEmpty else { return "" }
        currentPresetIndex = (currentPresetIndex - 1 + presetPaths.count) % presetPaths.count
        return loadPresetByIndex(currentPresetIndex)
    }

    func getCurrentPresetName() -> String {
        guard currentPresetIndex >= 0 && currentPresetIndex < presetPaths.count else { return "" }
        return decodedPresetName(presetPaths[currentPresetIndex])
    }

    private func decodedPresetName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".milk", with: "")
        return name.removingPercentEncoding ?? name
    }

    // MARK: - Parameters

    func setFps(_ fps: Int) {
        let maxFps = useFallbackReadback ? 30 : 60
        targetFps = max(15, min(maxFps, fps))
    }

    func setBeatSensitivity(_ sensitivity: Float) {
        guard let handle = pmHandle else { return }
        projectm_set_beat_sensitivity(handle, sensitivity)
    }

    func setPresetDuration(_ seconds: Double) {
        guard let handle = pmHandle else { return }
        projectm_set_preset_duration(handle, seconds)
    }

    func setPresetLocked(_ locked: Bool) {
        guard let handle = pmHandle else { return }
        projectm_set_preset_locked(handle, locked)
    }

    func setSize(_ w: Int, _ h: Int) {
        width = w
        height = h
        guard let handle = pmHandle else { return }
        projectm_set_window_size(handle, w, h)
    }

    func setMeshSize(_ w: Int, _ h: Int) {
        guard let handle = pmHandle else { return }
        projectm_set_mesh_size(handle, w, h)
    }
}
