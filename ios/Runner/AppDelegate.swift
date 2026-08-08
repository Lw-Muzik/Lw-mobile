import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
    private let dsp = DSPManager.shared
    private var visualizerTimer: CADisplayLink?
    private var visualizerChannel: FlutterMethodChannel?
    private var projectMRenderer: ProjectMRenderer?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        // Configure audio session for playback
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("AVAudioSession setup failed: \(error)")
        }

        // Initialize DSP engine
        let sampleRate = Int(session.sampleRate)
        dsp.initialize(sampleRate: sampleRate > 0 ? sampleRate : 48000)

        // Pass DSP handle to audio tap
        if let handle = dsp.handle {
            HypeAudioTap.shared().setDspHandle(handle)
        }

        // Set up MethodChannel
        if let controller = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(name: "eq_app",
                                                binaryMessenger: controller.binaryMessenger)
            channel.setMethodCallHandler { [weak self] call, result in
                self?.handleMethodCall(call, result: result)
            }

            // Separate channel for visualizer data (matches Android pattern)
            visualizerChannel = channel

            // Screen brightness, for the swipe gesture on the video screen.
            //
            // iOS has no per-window override, so this is the device brightness
            // and it persists after the app is closed — the same bargain every
            // iOS video player makes, and the reason the value is restored when
            // the full-screen route is left rather than on app exit.
            let brightnessChannel = FlutterMethodChannel(
                name: "eq_app/screen_brightness",
                binaryMessenger: controller.binaryMessenger)
            brightnessChannel.setMethodCallHandler { call, result in
                switch call.method {
                case "get":
                    result(Double(UIScreen.main.brightness))
                case "set":
                    let value = (call.arguments as? [String: Any])?["value"] as? Double
                    if let value = value {
                        UIScreen.main.brightness = CGFloat(min(max(value, 0.01), 1.0))
                    }
                    result(nil)
                default:
                    result(FlutterMethodNotImplemented)
                }
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - Open audio files from other apps (Safari, Files, AirDrop, etc.)

    override func application(_ app: UIApplication, open url: URL,
                              options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Check if this is an audio file
        let ext = url.pathExtension.lowercased()
        let audioExts: Set<String> = ["mp3", "m4a", "aac", "flac", "wav", "ogg", "wma", "aiff", "alac"]
        if audioExts.contains(ext) {
            copyToMusicFolder(url)
            return true
        }
        return super.application(app, open: url, options: options)
    }

    private func copyToMusicFolder(_ url: URL) {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let musicDir = docs.appendingPathComponent("Music")

        // Create Music directory if needed
        if !fm.fileExists(atPath: musicDir.path) {
            try? fm.createDirectory(at: musicDir, withIntermediateDirectories: true)
        }

        let destURL = musicDir.appendingPathComponent(url.lastPathComponent)

        // Access security-scoped resource (for files from other apps)
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: url, to: destURL)
            print("Hype: Imported \(url.lastPathComponent) to Music folder")

            // Notify Dart side that a new file was imported
            if let channel = visualizerChannel {
                DispatchQueue.main.async {
                    channel.invokeMethod("onFileImported", arguments: [
                        "path": destURL.path,
                        "name": url.lastPathComponent,
                    ])
                }
            }
        } catch {
            print("Hype: Failed to import \(url.lastPathComponent): \(error)")
        }
    }

    // MARK: - Visualizer Timer

    private func startVisualizerTimer() {
        guard visualizerTimer == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(sendVisualizerData))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        visualizerTimer = link
    }

    private func stopVisualizerTimer() {
        visualizerTimer?.invalidate()
        visualizerTimer = nil
    }

    @objc private func sendVisualizerData() {
        guard let channel = visualizerChannel else { return }
        let tap = HypeAudioTap.shared()

        // Send waveform as raw bytes (NSData → Uint8List in Dart, matches Android byte[])
        if let waveform = tap.latestWaveformBytes() {
            let args: [String: Any] = [
                "waveform": FlutterStandardTypedData(bytes: waveform),
                "sampleRate": tap.currentSampleRate()
            ]
            channel.invokeMethod("onWaveformVisualization", arguments: args)
        }

        if let fft = tap.latestFftBytes() {
            let args: [String: Any] = [
                "fft": FlutterStandardTypedData(bytes: fft)
            ]
            channel.invokeMethod("onFftVisualization", arguments: args)
        }
    }

    // MARK: - MethodChannel Handler

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        switch call.method {

        // ==================== EQ ====================
        case "init":
            result(nil)

        case "enableEq":
            let enable = args?["enable"] as? Bool ?? false
            dsp.setEqEnabled(enable)
            result(nil)

        case "isEnabled":
            result(true)

        case "setPreamp":
            let gain = floatArg(args, "gain")
            dsp.setPreampGain(gain)
            result(nil)

        case "getPreamp":
            result(Double(dsp.cachedPreampGain))

        case "enableMbc":
            let enable = args?["enable"] as? Bool ?? false
            dsp.setMbcEnabled(enable)
            result(nil)

        case "isMbcEnabled":
            result(dsp.cachedMbcEnabled)

        // ==================== Legacy EQ (safe defaults) ====================
        case "getPresetNames":
            result(["Flat", "Rock", "Pop", "Jazz", "Classical", "Bass Boost", "Treble Boost"])

        case "setPreset":
            result(nil)

        case "setBandLevel":
            result(nil)

        case "getBandLevelRange":
            result([-1500, 1500])

        case "getBandLevel":
            result(0)

        case "getSettings":
            result("")

        case "setSettings":
            result(nil)

        case "getBandFreq":
            result([60, 230, 910, 3600, 14000])

        // ==================== Bass Boost (legacy — handled by DSP pipeline) ====================
        case "initBassBoost":
            result(nil)

        case "enableBassBoost":
            result(nil)

        case "isBassEnabled":
            result(false)

        case "bassBoostStrength":
            result(0)

        case "setBassBoostStrength":
            result(nil)

        // ==================== Loudness Enhancer ====================
        case "initLoudnessEnhancer":
            result(nil)

        case "enableLoudnessEnhancer":
            result(nil)

        case "loudnessEnhancerEnabled":
            result(false)

        case "loudnessEnhancerStrength":
            result(0.0)

        case "setLoudnessEnhancerStrength":
            result(nil)

        // ==================== DVC (Limited on iOS) ====================
        case "enableDvc":
            result(nil)

        case "disableDvc":
            result(nil)

        case "setDvcGain":
            result(nil)

        case "getDvcGain":
            result(0.0)

        case "isDvcActive":
            result(false)

        case "getSystemVolume":
            let vol = AVAudioSession.sharedInstance().outputVolume
            result(Int(vol * 16))

        case "getSystemMaxVolume":
            result(16)

        // ==================== MBC Compressor ====================
        case "setDspNoiseThreshold":
            dsp.setMbcNoiseGate(floatArg(args, "noiseThreshold"))
            result(nil)

        case "setPreGain":
            dsp.setMbcPreGain(floatArg(args, "preGain"))
            result(nil)

        case "expandRatio":
            dsp.setMbcExpanderRatio(floatArg(args, "expandRatio"))
            result(nil)

        case "kneeWidth":
            dsp.setMbcKneeWidth(floatArg(args, "kneeWidth"))
            result(nil)

        // ==================== Tone Controls ====================
        case "dspSetToneEnabled":
            dsp.setToneEnabled(args?["enabled"] as? Bool ?? false)
            result(nil)

        case "dspSetBassGain":
            dsp.setBassGain(floatArg(args, "value"))
            result(nil)

        case "dspSetBassFreq":
            dsp.setBassFreq(floatArg(args, "value"))
            result(nil)

        case "dspSetBassQ":
            dsp.setBassQ(floatArg(args, "value"))
            result(nil)

        case "dspSetTrebleGain":
            dsp.setTrebleGain(floatArg(args, "value"))
            result(nil)

        case "dspSetTrebleFreq":
            dsp.setTrebleFreq(floatArg(args, "value"))
            result(nil)

        case "dspSetTrebleQ":
            dsp.setTrebleQ(floatArg(args, "value"))
            result(nil)

        // ==================== Output Limiter ====================
        case "dspSetLimiterEnabled":
            dsp.setLimiterEnabled(args?["enabled"] as? Bool ?? true)
            result(nil)

        case "dspSetLimiterCeiling":
            dsp.setLimiterCeiling(floatArg(args, "value"))
            result(nil)

        case "dspSetLimiterRelease":
            dsp.setLimiterRelease(floatArg(args, "value"))
            result(nil)

        case "dspSetLimiterKnee":
            dsp.setLimiterKnee(floatArg(args, "value"))
            result(nil)

        // ==================== 32-Band Graphic EQ ====================
        case "setGraphicBandGain":
            let band = args?["band"] as? Int ?? 0
            let gain = floatArg(args, "gain")
            dsp.setGraphicBandGain(band: band, dB: gain)
            result(nil)

        case "getGraphicBandGain":
            result(0.0)

        case "setGraphicAllBands":
            if let gains = args?["gains"] as? [Double] {
                dsp.setGraphicAllBands(gains.map { Float($0) })
            }
            result(nil)

        case "getGraphicAllBands":
            result([Double]())

        // ==================== 32-Band Parametric EQ ====================
        case "setParametricBand":
            let band = args?["band"] as? Int ?? 0
            let freq = floatArg(args, "freq")
            let gain = floatArg(args, "gain")
            let q = args?["q"] != nil ? floatArg(args, "q") : 1.4
            let filterType = args?["filterType"] as? Int ?? 0
            let enabled = args?["enabled"] as? Bool ?? true
            dsp.setParametricBand(band: band, freq: freq, gain: gain, q: q,
                                   filterType: filterType, enabled: enabled)
            result(nil)

        case "setParametricAllBands":
            if let freqs = args?["freqs"] as? [Double],
               let gains = args?["gains"] as? [Double] {
                let qs = (args?["qs"] as? [Double]) ?? Array(repeating: 1.4, count: freqs.count)
                dsp.setParametricAllBands(freqs: freqs.map { Float($0) },
                                           gains: gains.map { Float($0) },
                                           qs: qs.map { Float($0) })
            }
            result(nil)

        // ==================== Speaker Correction EQ ====================
        case "setSpeakerEqEnabled":
            dsp.setSpeakerEqEnabled(args?["enabled"] as? Bool ?? false)
            result(nil)

        case "setSpeakerEqBands":
            if let freqs = args?["freqs"] as? [Double],
               let gains = args?["gains"] as? [Double],
               let qs = args?["qs"] as? [Double],
               let types = args?["types"] as? [Int] {
                for i in 0..<min(freqs.count, gains.count, qs.count, types.count) {
                    dsp.setSpeakerEqBand(band: i, freq: Float(freqs[i]),
                                          gain: Float(gains[i]), q: Float(qs[i]),
                                          filterType: types[i], enabled: true)
                }
            }
            result(nil)

        case "clearSpeakerEq":
            dsp.clearSpeakerEq()
            result(nil)

        // ==================== Room Effects ====================
        case "dspSetReverbEnabled":
            dsp.setReverbEnabled(args?["enabled"] as? Bool ?? false)
            result(nil)

        case "dspSetRoomSize":
            dsp.setRoomSize(floatArg(args, "value"))
            result(nil)

        case "dspSetDecay":
            dsp.setDecay(floatArg(args, "value"))
            result(nil)

        case "dspSetDamping":
            dsp.setDamping(floatArg(args, "value"))
            result(nil)

        case "dspSetPreDelay":
            dsp.setPreDelay(floatArg(args, "value"))
            result(nil)

        case "dspSetDiffusion":
            dsp.setDiffusion(floatArg(args, "value"))
            result(nil)

        case "dspSetReverbWetDry":
            dsp.setReverbWetDry(floatArg(args, "value"))
            result(nil)

        case "dspSetStereoExpandEnabled":
            dsp.setStereoExpandEnabled(args?["enabled"] as? Bool ?? false)
            result(nil)

        case "dspSetStereoWidth":
            dsp.setStereoWidth(floatArg(args, "value"))
            result(nil)

        case "dspSetCrossfeedEnabled":
            dsp.setCrossfeedEnabled(args?["enabled"] as? Bool ?? false)
            result(nil)

        case "dspSetCrossfeedParams":
            let cutoff = floatArg(args, "cutoff")
            let feed = floatArg(args, "feed")
            dsp.setCrossfeedParams(cutoff: cutoff, feed: feed)
            result(nil)

        // ==================== Stem Separation ====================
        case "separateStems":
            result(false)

        case "cancelStemSeparation":
            result(nil)

        case "checkStemsExist":
            if let dirPath = args?["dirPath"] as? String {
                let fm = FileManager.default
                let exists = fm.fileExists(atPath: dirPath + "/vocals.wav")
                    && fm.fileExists(atPath: dirPath + "/drums.wav")
                    && fm.fileExists(atPath: dirPath + "/bass.wav")
                    && fm.fileExists(atPath: dirPath + "/other.wav")
                result(exists)
            } else {
                result(false)
            }

        // ==================== Stem Mixer ====================
        case "loadStems":
            if let vocals = args?["vocals"] as? String,
               let drums = args?["drums"] as? String,
               let bass = args?["bass"] as? String,
               let other = args?["other"] as? String {
                let ok = dsp.loadStems(vocals: vocals, drums: drums,
                                        bass: bass, other: other)
                result(ok)
            } else {
                result(false)
            }

        case "unloadStems":
            dsp.unloadStems()
            result(nil)

        case "activateStemMode":
            dsp.setStemModeActive(true)
            result(nil)

        case "deactivateStemMode":
            dsp.setStemModeActive(false)
            result(nil)

        case "setStemVolume":
            let stem = args?["stem"] as? Int ?? 0
            let vol = floatArg(args, "volume")
            dsp.setStemVolume(stem: stem, volume: vol)
            result(nil)

        case "setStemMute":
            let stem = args?["stem"] as? Int ?? 0
            let muted = args?["muted"] as? Bool ?? false
            dsp.setStemMute(stem: stem, muted: muted)
            result(nil)

        case "setStemSolo":
            let stem = args?["stem"] as? Int ?? 0
            let soloed = args?["soloed"] as? Bool ?? false
            dsp.setStemSolo(stem: stem, soloed: soloed)
            result(nil)

        case "stemSeek":
            let pos = args?["samplePosition"] as? Int64 ?? 0
            dsp.stemSeek(samplePosition: pos)
            result(nil)

        // ==================== Global EQ (Not available on iOS) ====================
        case "enableGlobalEq":
            result(false)

        case "isGlobalEqEnabled":
            result(false)

        case "isGlobalEqAvailable":
            result(false)

        // ==================== Device Detection ====================
        case "isDynamicsProcessingAvailable":
            result(true)

        case "getAudioOutputType":
            result(getAudioOutputType())

        // ==================== Audio Metadata Extraction ====================
        case "extractAudioMetadata":
            if let url = args?["url"] as? String {
                let artPath = args?["artworkPath"] as? String
                let headers = args?["headers"] as? [String: String] ?? [:]
                extractMetadata(url: url, headers: headers, artworkPath: artPath, result: result)
            } else {
                result(nil)
            }
            return // async

        // ==================== Audio Fingerprinting ====================
        case "generateFingerprint":
            result(nil)

        // ==================== Tag Writing ====================
        case "writeTags":
            result(false)

        case "scanMediaFile":
            result(nil)

        // ==================== Lyrics ====================
        case "readLyrics":
            if let filePath = args?["filePath"] as? String {
                result(readLyricsFromFile(filePath))
            } else {
                result(nil)
            }

        case "writeLyrics":
            result(false)

        // ==================== Visualizer ====================
        case "activate_visualizer":
            HypeAudioTap.shared().visualizerEnabled = true
            startVisualizerTimer()
            result(nil)

        case "enableVisual":
            let enable = args?["enableVisual"] as? Bool ?? false
            HypeAudioTap.shared().visualizerEnabled = enable
            if enable {
                startVisualizerTimer()
            } else {
                stopVisualizerTimer()
            }
            result(nil)

        case "getEnabled":
            result(HypeAudioTap.shared().visualizerEnabled)

        case "deactivate_visualizer":
            HypeAudioTap.shared().visualizerEnabled = false
            stopVisualizerTimer()
            result(nil)

        case "setScalingMode", "setFrameRate":
            result(nil)

        // ==================== projectM Visualizer ====================
        case "projectm_init":
            let w = args?["width"] as? Int ?? 720
            let h = args?["height"] as? Int ?? 480
            // Idempotent: release any existing renderer before creating a new
            // one. Without this, re-opening the visualizer (or reopening with a
            // new size) overwrote projectMRenderer, leaking the prior EAGL
            // context, FBOs/renderbuffers, CVPixelBuffers and the registered
            // Flutter texture.
            projectMRenderer?.release()
            projectMRenderer = nil
            if let controller = window?.rootViewController as? FlutterViewController {
                let renderer = ProjectMRenderer()
                let texId = renderer.initialize(
                    registrar: controller.engine.textureRegistry,
                    width: w, height: h
                )
                if let texId = texId {
                    projectMRenderer = renderer
                    // Enable visualization tap so projectM gets PCM data
                    HypeAudioTap.shared().visualizerEnabled = true
                    result(texId)
                } else {
                    result(-1)
                }
            } else {
                result(-1)
            }

        case "projectm_start":
            projectMRenderer?.start()
            result(nil)

        case "projectm_stop":
            projectMRenderer?.stop()
            result(nil)

        case "projectm_release":
            projectMRenderer?.release()
            projectMRenderer = nil
            result(nil)

        case "projectm_set_preset":
            if let path = args?["path"] as? String {
                result(projectMRenderer?.loadPresetByIndex(0) ?? "")
            } else {
                result("")
            }

        case "projectm_next_preset":
            result(projectMRenderer?.nextPreset() ?? "")

        case "projectm_prev_preset":
            result(projectMRenderer?.previousPreset() ?? "")

        case "projectm_load_preset_index":
            let index = args?["index"] as? Int ?? 0
            result(projectMRenderer?.loadPresetByIndex(index) ?? "")

        case "projectm_list_presets":
            result(projectMRenderer?.listPresets() ?? [String]())

        case "projectm_current_preset":
            result(projectMRenderer?.getCurrentPresetName() ?? "")

        case "projectm_set_fps":
            let fps = args?["fps"] as? Int ?? 30
            projectMRenderer?.setFps(fps)
            result(nil)

        case "projectm_set_beat_sensitivity":
            let sensitivity = floatArg(args, "sensitivity")
            projectMRenderer?.setBeatSensitivity(sensitivity)
            result(nil)

        case "projectm_set_preset_duration":
            let seconds = args?["seconds"] as? Double ?? 30.0
            projectMRenderer?.setPresetDuration(seconds)
            result(nil)

        case "projectm_set_preset_locked":
            let locked = args?["locked"] as? Bool ?? false
            projectMRenderer?.setPresetLocked(locked)
            result(nil)

        case "projectm_set_size":
            let w = args?["width"] as? Int ?? 720
            let h = args?["height"] as? Int ?? 480
            projectMRenderer?.setSize(w, h)
            result(nil)

        case "projectm_set_mesh_size":
            let w = args?["width"] as? Int ?? 32
            let h = args?["height"] as? Int ?? 24
            projectMRenderer?.setMeshSize(w, h)
            result(nil)

        // ==================== Preset Reverb (legacy) ====================
        case "initPresetReverb", "enablePresetReverb", "setReverbPreset":
            result(nil)

        case "getReverbPreset":
            result(0)

        // ==================== Delete Manager ====================
        case "deleteManager":
            if let path = args?["filePath"] as? String {
                try? FileManager.default.removeItem(atPath: path)
            }
            result(nil)

        case "showNativeMessage":
            result(nil)

        // ==================== Legacy DSP stubs ====================
        case "initDSPEngine", "enableDSP", "disposeDSP", "setDSPSpeakers",
             "setDSPXBass", "setExtraBass", "setDSPPowerBass", "setDSPXTreble",
             "setDSPVolume", "setTunerBass", "setCutOffFreq", "setTrebleFreq",
             "setTunerVocal":
            result(nil)

        case "getVocalLevel":
            result(0.0)

        case "release":
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Helpers

    private func floatArg(_ args: [String: Any]?, _ key: String) -> Float {
        if let v = args?[key] as? Double { return Float(v) }
        if let v = args?[key] as? Int { return Float(v) }
        if let v = args?[key] as? Float { return v }
        return 0.0
    }

    private func getAudioOutputType() -> String {
        let route = AVAudioSession.sharedInstance().currentRoute
        for output in route.outputs {
            switch output.portType {
            case .headphones, .headsetMic:
                return "headset"
            case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
                return "bluetooth"
            case .builtInSpeaker:
                return "speaker"
            case .airPlay:
                return "airplay"
            case .carAudio:
                return "car"
            default:
                return "other"
            }
        }
        return "speaker"
    }

    private func extractMetadata(url: String, headers: [String: String],
                                  artworkPath: String?,
                                  result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            var metadata: [String: Any] = [:]
            var asset: AVAsset?

            if url.hasPrefix("http://") || url.hasPrefix("https://") {
                guard let assetUrl = URL(string: url) else {
                    DispatchQueue.main.async { result(nil) }
                    return
                }
                if headers.isEmpty {
                    asset = AVURLAsset(url: assetUrl)
                } else {
                    asset = AVURLAsset(url: assetUrl, options: [
                        "AVURLAssetHTTPHeaderFieldsKey": headers
                    ])
                }
            } else {
                let fileUrl = URL(fileURLWithPath: url)
                guard FileManager.default.fileExists(atPath: url) else {
                    DispatchQueue.main.async { result(nil) }
                    return
                }
                asset = AVURLAsset(url: fileUrl)
            }

            guard let avAsset = asset else {
                DispatchQueue.main.async { result(nil) }
                return
            }

            for item in avAsset.commonMetadata {
                if let key = item.commonKey {
                    switch key {
                    case .commonKeyTitle:
                        metadata["title"] = item.stringValue
                    case .commonKeyArtist:
                        metadata["artist"] = item.stringValue
                    case .commonKeyAlbumName:
                        metadata["album"] = item.stringValue
                    case .commonKeyArtwork:
                        if let artPath = artworkPath, let data = item.dataValue {
                            try? data.write(to: URL(fileURLWithPath: artPath))
                            metadata["hasArtwork"] = true
                        }
                    default:
                        break
                    }
                }
            }

            let durationMs = Int(CMTimeGetSeconds(avAsset.duration) * 1000)
            if durationMs > 0 {
                metadata["durationMs"] = durationMs
            }

            DispatchQueue.main.async {
                result(metadata)
            }
        }
    }

    private func readLyricsFromFile(_ filePath: String) -> String? {
        let url = URL(fileURLWithPath: filePath)
        let asset = AVURLAsset(url: url)

        for item in asset.metadata {
            if let key = item.identifier,
               key.rawValue.contains("lyrics") || key.rawValue.contains("USLT") {
                return item.stringValue
            }
        }

        if let lyrics = asset.lyrics {
            return lyrics
        }

        return nil
    }
}
