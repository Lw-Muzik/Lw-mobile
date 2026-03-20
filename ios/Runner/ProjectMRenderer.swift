import Flutter
import OpenGLES
import AVFoundation

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
    private var colorRenderbuffer: GLuint = 0
    private var glTexture: GLuint = 0

    // CVPixelBuffer for Flutter texture sharing
    private var pixelBuffer: CVPixelBuffer?
    private var textureCache: CVOpenGLESTextureCache?
    private var cvTexture: CVOpenGLESTexture?

    // projectM handle
    private var pmHandle: OpaquePointer?

    // Render loop
    private var renderThread: Thread?
    private var rendering = false
    private var targetFps: Int = 30

    // Presets
    private var presetPaths: [String] = []
    private var currentPresetIndex: Int = 0

    // MARK: - Public API

    func initialize(registrar: FlutterTextureRegistry, width: Int, height: Int) -> Int64? {
        self.registrar = registrar
        self.width = width
        self.height = height

        // Create OpenGL ES 3.0 context
        guard let context = EAGLContext(api: .openGLES3) else {
            print("ProjectM: Failed to create EAGL context")
            return nil
        }
        eaglContext = context

        // Set up on GL thread
        EAGLContext.setCurrent(context)

        // Create CVOpenGLESTextureCache for sharing with Flutter
        var cache: CVOpenGLESTextureCache?
        let cacheResult = CVOpenGLESTextureCacheCreate(
            kCFAllocatorDefault, nil,
            context, nil, &cache
        )
        guard cacheResult == kCVReturnSuccess, let textureCache = cache else {
            print("ProjectM: Failed to create texture cache")
            return nil
        }
        self.textureCache = textureCache

        // Create CVPixelBuffer
        let attrs: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferOpenGLESCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        guard let pixelBuffer = pb else {
            print("ProjectM: Failed to create pixel buffer")
            return nil
        }
        self.pixelBuffer = pixelBuffer

        // Create GL texture from CVPixelBuffer
        var cvTex: CVOpenGLESTexture?
        CVOpenGLESTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            GLenum(GL_TEXTURE_2D), GL_RGBA,
            GLsizei(width), GLsizei(height),
            GLenum(GL_BGRA), GLenum(GL_UNSIGNED_BYTE),
            0, &cvTex
        )
        guard let texture = cvTex else {
            print("ProjectM: Failed to create CV texture")
            return nil
        }
        self.cvTexture = texture
        glTexture = CVOpenGLESTextureGetName(texture)

        // Set up framebuffer rendering to this texture
        glGenFramebuffers(1, &framebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                               GLenum(GL_TEXTURE_2D), glTexture, 0)

        let fbStatus = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if fbStatus != GLenum(GL_FRAMEBUFFER_COMPLETE) {
            print("ProjectM: Framebuffer incomplete: \(fbStatus)")
            return nil
        }

        // Create projectM instance
        pmHandle = projectm_create()
        guard pmHandle != nil else {
            print("ProjectM: projectm_create() failed — GL context may not be ready")
            return nil
        }
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
        renderThread = nil
    }

    func release() {
        stop()

        // Wait for render thread to finish
        Thread.sleep(forTimeInterval: 0.1)

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

        while rendering {
            let frameStart = CACurrentMediaTime()

            // Bind our framebuffer
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
            glViewport(0, 0, GLsizei(width), GLsizei(height))

            // Feed PCM audio data from the visualization tap
            feedAudioData()

            // Render projectM frame
            if let handle = pmHandle {
                projectm_opengl_render_frame(handle)
            }

            glFlush()

            // Notify Flutter that a new frame is ready
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.textureId >= 0 else { return }
                self.registrar?.textureFrameAvailable(self.textureId)
            }

            // Frame rate limiting
            let elapsed = CACurrentMediaTime() - frameStart
            let targetInterval = 1.0 / Double(targetFps)
            let sleepTime = targetInterval - elapsed
            if sleepTime > 0 {
                Thread.sleep(forTimeInterval: sleepTime)
            }
        }

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
            if !presetPaths.isEmpty { return }
        }

        // Extract from Flutter asset bundle
        guard let flutterAssetsPath = Bundle.main.path(forResource: "flutter_assets", ofType: nil) else { return }
        let srcDir = (flutterAssetsPath as NSString).appendingPathComponent("assets/milkdrop_presets")

        guard let files = try? fm.contentsOfDirectory(atPath: srcDir) else { return }
        let milkFiles = files.filter { $0.hasSuffix(".milk") }
        guard !milkFiles.isEmpty else { return }

        try? fm.createDirectory(atPath: presetsDir, withIntermediateDirectories: true)
        for file in milkFiles {
            let src = (srcDir as NSString).appendingPathComponent(file)
            let dst = (presetsDir as NSString).appendingPathComponent(file)
            if !fm.fileExists(atPath: dst) {
                try? fm.copyItem(atPath: src, toPath: dst)
            }
        }

        loadPresetsFromDirectory(presetsDir)
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
        return presetPaths.map { url in
            (url as NSString).lastPathComponent
                .replacingOccurrences(of: ".milk", with: "")
        }
    }

    func loadPresetByIndex(_ index: Int) -> String {
        guard index >= 0 && index < presetPaths.count else { return "" }
        currentPresetIndex = index
        let path = presetPaths[index]

        // Must load on GL thread
        if Thread.current.name == "projectm-gl" {
            projectm_load_preset_file(pmHandle, path, true)
        } else {
            // Queue for next frame
            DispatchQueue.global().async { [weak self] in
                guard let self = self, let ctx = self.eaglContext else { return }
                EAGLContext.setCurrent(ctx)
                projectm_load_preset_file(self.pmHandle, path, true)
            }
        }

        return (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".milk", with: "")
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
        return (presetPaths[currentPresetIndex] as NSString).lastPathComponent
            .replacingOccurrences(of: ".milk", with: "")
    }

    // MARK: - Parameters

    func setFps(_ fps: Int) {
        targetFps = max(15, min(60, fps))
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
