import Flutter
import OpenGLES
import CoreVideo
import AVFoundation

private let GL_BGRA_EXT = GLenum(0x80E1)

/// ProjectM renderer for iOS.
/// Key insight: projectM hardcodes glBindFramebuffer(0) for its final output,
/// so we render to FBO 0 (a color renderbuffer), then blit to our CVPixelBuffer FBO.
class ProjectMRenderer: NSObject, FlutterTexture {
    private var registrar: FlutterTextureRegistry?
    private var textureId: Int64 = -1
    private var width: Int = 720
    private var height: Int = 480

    // OpenGL ES
    private var eaglContext: EAGLContext?

    // FBO 0: projectM renders here (color renderbuffer + depth)
    private var defaultFBO: GLuint = 0
    private var colorRBO: GLuint = 0
    private var depthRBO: GLuint = 0

    // Resolve FBO: CVPixelBuffer-backed texture for Flutter display
    private var resolveFBOs: [GLuint] = [0, 0]
    private var resolveTextures: [GLuint] = [0, 0]
    private var pixelBuffers: [CVPixelBuffer?] = [nil, nil]
    private var cvTextures: [CVOpenGLESTexture?] = [nil, nil]
    private var textureCache: CVOpenGLESTextureCache?
    private var displayBuffer: CVPixelBuffer?
    private var currentIdx: Int = 0
    private var zeroCopy = false

    // projectM
    private var pmHandle: OpaquePointer?

    // Render loop
    private var renderThread: Thread?
    private var rendering = false
    private var targetFps: Int = 30

    // Guards release() against double-free (explicit release + deinit).
    private var released = false

    // Presets
    private var pendingPresetPath: String?
    private let presetLock = NSLock()
    private var presetPaths: [String] = []
    private var currentPresetIndex: Int = 0

    // MARK: - Init

    func initialize(registrar: FlutterTextureRegistry, width: Int, height: Int) -> Int64? {
        self.registrar = registrar
        self.width = max(width, 2)
        self.height = max(height, 2)

        guard let ctx = EAGLContext(api: .openGLES3) ?? EAGLContext(api: .openGLES2) else {
            print("ProjectM: No EAGL context"); return nil
        }
        eaglContext = ctx
        EAGLContext.setCurrent(ctx)

        // Texture cache
        var cache: CVOpenGLESTextureCache?
        guard CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, ctx, nil, &cache) == kCVReturnSuccess,
              let tc = cache else { print("ProjectM: No texture cache"); return nil }
        textureCache = tc

        // --- FBO 0: where projectM renders its final output ---
        glGenFramebuffers(1, &defaultFBO)
        glGenRenderbuffers(1, &colorRBO)
        glGenRenderbuffers(1, &depthRBO)

        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), defaultFBO)

        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRBO)
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER), GLenum(GL_RGBA8),
                              GLsizei(self.width), GLsizei(self.height))
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                                  GLenum(GL_RENDERBUFFER), colorRBO)

        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), depthRBO)
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER), GLenum(GL_DEPTH_COMPONENT16),
                              GLsizei(self.width), GLsizei(self.height))
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_DEPTH_ATTACHMENT),
                                  GLenum(GL_RENDERBUFFER), depthRBO)

        guard glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) == GLenum(GL_FRAMEBUFFER_COMPLETE) else {
            print("ProjectM: Default FBO incomplete"); return nil
        }

        // --- Resolve FBOs: CVPixelBuffer-backed for Flutter ---
        zeroCopy = true
        for i in 0..<2 {
            let attrs: NSDictionary = [
                kCVPixelBufferIOSurfacePropertiesKey: NSDictionary(),
                kCVPixelBufferOpenGLESCompatibilityKey: true,
            ]
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, self.width, self.height,
                                kCVPixelFormatType_32BGRA, attrs, &pb)
            guard let pixelBuffer = pb else { print("ProjectM: No PB \(i)"); return nil }
            pixelBuffers[i] = pixelBuffer

            var cvTex: CVOpenGLESTexture?
            let st = CVOpenGLESTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, tc, pixelBuffer, nil,
                GLenum(GL_TEXTURE_2D), GLint(GL_RGBA),
                GLsizei(self.width), GLsizei(self.height),
                GL_BGRA_EXT, GLenum(GL_UNSIGNED_BYTE), 0, &cvTex)

            var fbo: GLuint = 0
            glGenFramebuffers(1, &fbo)
            resolveFBOs[i] = fbo

            if st == kCVReturnSuccess, let tex = cvTex {
                cvTextures[i] = tex
                let glTex = CVOpenGLESTextureGetName(tex)
                resolveTextures[i] = glTex
                glBindTexture(GLenum(GL_TEXTURE_2D), glTex)
                glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
                glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)

                glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
                glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                                       GLenum(GL_TEXTURE_2D), glTex, 0)
            } else {
                // Fallback: plain GL texture
                zeroCopy = false
                var tex: GLuint = 0
                glGenTextures(1, &tex)
                resolveTextures[i] = tex
                glBindTexture(GLenum(GL_TEXTURE_2D), tex)
                glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA,
                             GLsizei(self.width), GLsizei(self.height), 0,
                             GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
                glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
                glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)

                glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
                glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                                       GLenum(GL_TEXTURE_2D), tex, 0)
            }
        }
        print("ProjectM: zeroCopy=\(zeroCopy), \(self.width)x\(self.height)")

        // Create projectM with defaultFBO bound
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), defaultFBO)
        glViewport(0, 0, GLsizei(self.width), GLsizei(self.height))

        pmHandle = projectm_create()
        guard pmHandle != nil else {
            print("ProjectM: projectm_create failed"); extractPresets()
            EAGLContext.setCurrent(nil); return nil
        }
        projectm_set_window_size(pmHandle, self.width, self.height)

        extractPresets()
        displayBuffer = pixelBuffers[1]
        textureId = registrar.register(self)
        EAGLContext.setCurrent(nil)
        print("ProjectM: Ready, textureId=\(textureId)")
        return textureId
    }

    func start() {
        guard !rendering, pmHandle != nil else { return }
        rendering = true
        let t = Thread(target: self, selector: #selector(renderLoop), object: nil)
        t.name = "projectm-gl"
        t.qualityOfService = .userInteractive
        renderThread = t
        t.start()
    }

    func stop() {
        rendering = false
        while renderThread?.isExecuting == true { Thread.sleep(forTimeInterval: 0.01) }
        renderThread = nil
    }

    func release() {
        // Idempotent: safe to call from projectm_release, from projectm_init
        // (releasing a previous renderer), and from deinit.
        if released { return }
        released = true
        stop()
        guard let ctx = eaglContext else { return }
        EAGLContext.setCurrent(ctx)

        if let h = pmHandle { projectm_destroy(h); pmHandle = nil }
        if defaultFBO != 0 { glDeleteFramebuffers(1, &defaultFBO) }
        if colorRBO != 0 { glDeleteRenderbuffers(1, &colorRBO) }
        if depthRBO != 0 { glDeleteRenderbuffers(1, &depthRBO) }
        for i in 0..<2 {
            if resolveFBOs[i] != 0 { glDeleteFramebuffers(1, &resolveFBOs[i]) }
            if cvTextures[i] == nil && resolveTextures[i] != 0 { glDeleteTextures(1, &resolveTextures[i]) }
            cvTextures[i] = nil; pixelBuffers[i] = nil
        }
        if let c = textureCache { CVOpenGLESTextureCacheFlush(c, 0) }
        textureCache = nil
        EAGLContext.setCurrent(nil); eaglContext = nil
        if textureId >= 0 { registrar?.unregisterTexture(textureId); textureId = -1 }
    }

    deinit {
        // Safety net: if this renderer is dropped without an explicit
        // release() (e.g. AppDelegate reassigns projectMRenderer without
        // calling release first), tear down GL/CV/texture resources here.
        // release() is idempotent, so a prior explicit release is a no-op.
        release()
    }

    // MARK: - FlutterTexture

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let pb = displayBuffer else { return nil }
        return Unmanaged.passRetained(pb)
    }

    // MARK: - Render Loop

    @objc private func renderLoop() {
        guard let ctx = eaglContext else { return }
        EAGLContext.setCurrent(ctx)

        // For non-zero-copy: readback buffer
        let rowBytes = width * 4
        var readBuf: UnsafeMutableRawPointer?
        if !zeroCopy {
            readBuf = .allocate(byteCount: rowBytes * height, alignment: 16)
            targetFps = min(targetFps, 20)
        }

        while rendering {
            let t0 = CACurrentMediaTime()
            guard let handle = pmHandle else { break }

            // Pending preset
            presetLock.lock()
            let pp = pendingPresetPath; pendingPresetPath = nil
            presetLock.unlock()
            if let p = pp { projectm_load_preset_file(handle, p, true) }

            // 1) Render projectM to defaultFBO (it binds FBO 0 internally,
            //    but we made defaultFBO our "FBO 0" by binding it before create)
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), defaultFBO)
            glViewport(0, 0, GLsizei(width), GLsizei(height))
            feedAudioData()
            projectm_opengl_render_frame(handle)

            // 2) Blit from defaultFBO to resolve FBO (CVPixelBuffer-backed)
            let resolveIdx = currentIdx
            glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), defaultFBO)
            glBindFramebuffer(GLenum(GL_DRAW_FRAMEBUFFER), resolveFBOs[resolveIdx])
            glBlitFramebuffer(0, 0, GLint(width), GLint(height),
                              0, 0, GLint(width), GLint(height),
                              GLbitfield(GL_COLOR_BUFFER_BIT), GLenum(GL_NEAREST))

            if !zeroCopy, let pb = pixelBuffers[resolveIdx], let buf = readBuf {
                // Readback fallback: read from resolve FBO
                glBindFramebuffer(GLenum(GL_FRAMEBUFFER), resolveFBOs[resolveIdx])
                glFinish()
                glReadPixels(0, 0, GLsizei(width), GLsizei(height),
                             GL_BGRA_EXT, GLenum(GL_UNSIGNED_BYTE), buf)
                // Flip vertically
                CVPixelBufferLockBaseAddress(pb, [])
                if let dest = CVPixelBufferGetBaseAddress(pb) {
                    let stride = CVPixelBufferGetBytesPerRow(pb)
                    for row in 0..<height {
                        memcpy(dest.advanced(by: row * stride),
                               buf.advanced(by: (height - 1 - row) * rowBytes), rowBytes)
                    }
                }
                CVPixelBufferUnlockBaseAddress(pb, [])
            } else {
                glFlush()
            }

            // Swap display buffer
            displayBuffer = pixelBuffers[resolveIdx]
            currentIdx = 1 - resolveIdx

            if rendering, textureId >= 0 {
                DispatchQueue.main.async { [weak self] in
                    guard let s = self, s.rendering, s.textureId >= 0 else { return }
                    s.registrar?.textureFrameAvailable(s.textureId)
                }
            }

            let elapsed = CACurrentMediaTime() - t0
            let budget = 1.0 / Double(targetFps)
            if elapsed < budget { Thread.sleep(forTimeInterval: budget - elapsed) }
        }

        readBuf?.deallocate()
        EAGLContext.setCurrent(nil)
    }

    private func feedAudioData() {
        guard let h = pmHandle, let pcm = HypeAudioTap.shared().latestPcmFloat() else { return }
        pcm.withUnsafeBytes { raw in
            guard let p = raw.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
            projectm_pcm_add_float(h, p, UInt32(pcm.count / 4), PROJECTM_MONO)
        }
    }

    // MARK: - Presets

    private func extractPresets() {
        let fm = FileManager.default
        let cachePath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first!
        let dir = (cachePath as NSString).appendingPathComponent("milkdrop_presets")

        if fm.fileExists(atPath: dir) {
            loadPresetsFrom(dir)
            if !presetPaths.isEmpty { return }
        }

        let candidates: [String] = [
            Bundle.main.privateFrameworksPath.map { ($0 as NSString).appendingPathComponent("App.framework/flutter_assets/assets/milkdrop_presets") },
            Bundle.main.resourcePath.map { ($0 as NSString).appendingPathComponent("Frameworks/App.framework/flutter_assets/assets/milkdrop_presets") },
            Bundle.main.path(forResource: "flutter_assets", ofType: nil).map { ($0 as NSString).appendingPathComponent("assets/milkdrop_presets") },
        ].compactMap { $0 }

        guard let src = candidates.first(where: { fm.fileExists(atPath: $0) }),
              let files = try? fm.contentsOfDirectory(atPath: src) else { return }
        let milks = files.filter { $0.hasSuffix(".milk") }
        guard !milks.isEmpty else { return }

        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for f in milks {
            let dst = (dir as NSString).appendingPathComponent(f)
            if !fm.fileExists(atPath: dst) { try? fm.copyItem(atPath: (src as NSString).appendingPathComponent(f), toPath: dst) }
        }
        loadPresetsFrom(dir)
    }

    private func loadPresetsFrom(_ dir: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        presetPaths = files.filter { $0.hasSuffix(".milk") }.sorted()
            .map { (dir as NSString).appendingPathComponent($0) }
        if let h = pmHandle, !presetPaths.isEmpty {
            var cStr: UnsafePointer<CChar>? = (dir as NSString).utf8String
            withUnsafeMutablePointer(to: &cStr) { projectm_set_texture_search_paths(h, $0, 1) }
            projectm_load_preset_file(h, presetPaths[0], true)
        }
    }

    private func dn(_ p: String) -> String {
        let n = (p as NSString).lastPathComponent.replacingOccurrences(of: ".milk", with: "")
        return n.removingPercentEncoding ?? n
    }

    func listPresets() -> [String] { presetPaths.map { dn($0) } }
    func getCurrentPresetName() -> String {
        currentPresetIndex < presetPaths.count ? dn(presetPaths[currentPresetIndex]) : ""
    }
    func loadPresetByIndex(_ i: Int) -> String {
        guard i >= 0 && i < presetPaths.count else { return "" }
        currentPresetIndex = i
        presetLock.lock(); pendingPresetPath = presetPaths[i]; presetLock.unlock()
        return dn(presetPaths[i])
    }
    func nextPreset() -> String {
        guard !presetPaths.isEmpty else { return "" }
        return loadPresetByIndex((currentPresetIndex + 1) % presetPaths.count)
    }
    func previousPreset() -> String {
        guard !presetPaths.isEmpty else { return "" }
        return loadPresetByIndex((currentPresetIndex - 1 + presetPaths.count) % presetPaths.count)
    }

    func setFps(_ fps: Int) { targetFps = max(15, min(zeroCopy ? 60 : 24, fps)) }
    func setBeatSensitivity(_ s: Float) { pmHandle.map { projectm_set_beat_sensitivity($0, s) } }
    func setPresetDuration(_ s: Double) { pmHandle.map { projectm_set_preset_duration($0, s) } }
    func setPresetLocked(_ l: Bool) { pmHandle.map { projectm_set_preset_locked($0, l) } }
    func setSize(_ w: Int, _ h: Int) { width = w; height = h; pmHandle.map { projectm_set_window_size($0, w, h) } }
    func setMeshSize(_ w: Int, _ h: Int) { pmHandle.map { projectm_set_mesh_size($0, w, h) } }
}
