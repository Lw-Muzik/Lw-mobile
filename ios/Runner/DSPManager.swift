import Foundation
import AVFoundation
import Flutter

/// Manages the C++ DSP engine lifecycle and provides a singleton for parameter updates.
/// The actual audio processing tap is installed by AudioDSPTap on the AVAudioEngine.
class DSPManager {
    static let shared = DSPManager()

    private(set) var handle: UnsafeMutableRawPointer?
    private var sampleRate: Int = 48000
    private var channels: Int = 2

    // Cached preamp for getter
    private(set) var cachedPreampGain: Float = 0.0
    private(set) var cachedMbcEnabled: Bool = false

    private init() {}

    func initialize(sampleRate: Int = 48000, channels: Int = 2) {
        self.sampleRate = sampleRate
        self.channels = channels
        if handle == nil {
            handle = dsp_create(Int32(sampleRate), Int32(channels))
        } else {
            dsp_reinit(handle, Int32(sampleRate), Int32(channels))
        }
    }

    func destroy() {
        if let h = handle {
            dsp_destroy(h)
            handle = nil
        }
    }

    func reinit(sampleRate: Int, channels: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
        if let h = handle {
            dsp_reinit(h, Int32(sampleRate), Int32(channels))
        } else {
            handle = dsp_create(Int32(sampleRate), Int32(channels))
        }
    }

    func process(buffer: UnsafeMutablePointer<Float>, numFrames: Int) {
        guard let h = handle else { return }
        dsp_process_float(h, buffer, Int32(numFrames))
    }

    // MARK: - EQ

    func setEqEnabled(_ enabled: Bool) {
        guard let h = handle else { return }
        dsp_set_eq_enabled(h, enabled)
    }

    func setPreampGain(_ dB: Float) {
        cachedPreampGain = dB
        guard let h = handle else { return }
        dsp_set_preamp_gain(h, dB)
    }

    func setGraphicBandGain(band: Int, dB: Float) {
        guard let h = handle else { return }
        dsp_set_graphic_band_gain(h, Int32(band), dB)
    }

    func setGraphicAllBands(_ gains: [Float]) {
        guard let h = handle else { return }
        gains.withUnsafeBufferPointer { ptr in
            dsp_set_graphic_all_bands(h, ptr.baseAddress, Int32(gains.count))
        }
    }

    func setParametricBand(band: Int, freq: Float, gain: Float, q: Float,
                           filterType: Int, enabled: Bool) {
        guard let h = handle else { return }
        dsp_set_parametric_band(h, Int32(band), freq, gain, q, Int32(filterType), enabled)
    }

    func setParametricAllBands(freqs: [Float], gains: [Float], qs: [Float]) {
        guard let h = handle else { return }
        let count = min(freqs.count, gains.count, qs.count)
        freqs.withUnsafeBufferPointer { f in
            gains.withUnsafeBufferPointer { g in
                qs.withUnsafeBufferPointer { q in
                    dsp_set_parametric_all_bands(h, f.baseAddress, g.baseAddress,
                                                  q.baseAddress, Int32(count))
                }
            }
        }
    }

    // MARK: - Speaker Correction EQ

    func setSpeakerEqEnabled(_ enabled: Bool) {
        guard let h = handle else { return }
        dsp_set_speaker_eq_enabled(h, enabled)
    }

    func setSpeakerEqBand(band: Int, freq: Float, gain: Float, q: Float,
                          filterType: Int, enabled: Bool) {
        guard let h = handle else { return }
        dsp_set_speaker_eq_band(h, Int32(band), freq, gain, q, Int32(filterType), enabled)
    }

    func clearSpeakerEq() {
        guard let h = handle else { return }
        dsp_clear_speaker_eq(h)
    }

    // MARK: - Tone Controls

    func setToneEnabled(_ enabled: Bool) {
        guard let h = handle else { return }
        dsp_set_tone_enabled(h, enabled)
    }

    func setBassGain(_ dB: Float) {
        guard let h = handle else { return }
        dsp_set_bass_gain(h, dB)
    }

    func setBassFreq(_ hz: Float) {
        guard let h = handle else { return }
        dsp_set_bass_freq(h, hz)
    }

    func setBassQ(_ q: Float) {
        guard let h = handle else { return }
        dsp_set_bass_q(h, q)
    }

    func setTrebleGain(_ dB: Float) {
        guard let h = handle else { return }
        dsp_set_treble_gain(h, dB)
    }

    func setTrebleFreq(_ hz: Float) {
        guard let h = handle else { return }
        dsp_set_treble_freq(h, hz)
    }

    func setTrebleQ(_ q: Float) {
        guard let h = handle else { return }
        dsp_set_treble_q(h, q)
    }

    // MARK: - Limiter

    func setLimiterEnabled(_ enabled: Bool) {
        guard let h = handle else { return }
        dsp_set_limiter_enabled(h, enabled)
    }

    func setLimiterCeiling(_ v: Float) {
        guard let h = handle else { return }
        dsp_set_limiter_ceiling(h, v)
    }

    func setLimiterRelease(_ ms: Float) {
        guard let h = handle else { return }
        dsp_set_limiter_release(h, ms)
    }

    func setLimiterKnee(_ dB: Float) {
        guard let h = handle else { return }
        dsp_set_limiter_knee(h, dB)
    }

    // MARK: - MBC

    func setMbcEnabled(_ enabled: Bool) {
        cachedMbcEnabled = enabled
        guard let h = handle else { return }
        dsp_set_mbc_enabled(h, enabled)
    }

    func setMbcPreGain(_ dB: Float) {
        guard let h = handle else { return }
        dsp_set_mbc_pre_gain(h, dB)
    }

    func setMbcNoiseGate(_ dB: Float) {
        guard let h = handle else { return }
        dsp_set_mbc_noise_gate(h, dB)
    }

    func setMbcKneeWidth(_ dB: Float) {
        guard let h = handle else { return }
        dsp_set_mbc_knee_width(h, dB)
    }

    func setMbcExpanderRatio(_ ratio: Float) {
        guard let h = handle else { return }
        dsp_set_mbc_expander_ratio(h, ratio)
    }

    func setMbcThreshold(_ dB: Float) {
        guard let h = handle else { return }
        dsp_set_mbc_threshold(h, dB)
    }

    func setMbcRatio(_ ratio: Float) {
        guard let h = handle else { return }
        dsp_set_mbc_ratio(h, ratio)
    }

    func setMbcAttackTime(_ ms: Float) {
        guard let h = handle else { return }
        dsp_set_mbc_attack_time(h, ms)
    }

    func setMbcReleaseTime(_ ms: Float) {
        guard let h = handle else { return }
        dsp_set_mbc_release_time(h, ms)
    }

    func setMbcPostGain(_ dB: Float) {
        guard let h = handle else { return }
        dsp_set_mbc_post_gain(h, dB)
    }

    // MARK: - Reverb

    func setReverbEnabled(_ enabled: Bool) {
        guard let h = handle else { return }
        dsp_set_reverb_enabled(h, enabled)
    }

    func setRoomSize(_ v: Float) {
        guard let h = handle else { return }
        dsp_set_room_size(h, v)
    }

    func setDecay(_ v: Float) {
        guard let h = handle else { return }
        dsp_set_decay(h, v)
    }

    func setDamping(_ v: Float) {
        guard let h = handle else { return }
        dsp_set_damping(h, v)
    }

    func setPreDelay(_ ms: Float) {
        guard let h = handle else { return }
        dsp_set_pre_delay(h, ms)
    }

    func setDiffusion(_ v: Float) {
        guard let h = handle else { return }
        dsp_set_diffusion(h, v)
    }

    func setReverbWetDry(_ v: Float) {
        guard let h = handle else { return }
        dsp_set_reverb_wet_dry(h, v)
    }

    // MARK: - Stereo Expander

    func setStereoExpandEnabled(_ enabled: Bool) {
        guard let h = handle else { return }
        dsp_set_stereo_expand_enabled(h, enabled)
    }

    func setStereoWidth(_ width: Float) {
        guard let h = handle else { return }
        dsp_set_stereo_width(h, width)
    }

    // MARK: - Crossfeed

    func setCrossfeedEnabled(_ enabled: Bool) {
        guard let h = handle else { return }
        dsp_set_crossfeed_enabled(h, enabled)
    }

    func setCrossfeedParams(cutoff: Float, feed: Float) {
        guard let h = handle else { return }
        dsp_set_crossfeed_params(h, cutoff, feed)
    }

    // MARK: - 3D Surround
    //
    // Same stage, same constants and the same channel names as Android — the
    // whole point of the port is that the two platforms sound alike, so the
    // Dart side must not need to know which one it is talking to.

    func setSurround3dEnabled(_ enabled: Bool) {
        guard let h = handle else { return }
        dsp_set_surround3d_enabled(h, enabled)
    }

    func setSurround3dParams(intensity: Float, subwoofer: Float) {
        guard let h = handle else { return }
        dsp_set_surround3d_params(h, intensity, subwoofer)
    }

    func setSurround3dSpeakers(frontL: Bool, frontR: Bool, sideL: Bool,
                               sideR: Bool, surroundL: Bool, surroundR: Bool) {
        guard let h = handle else { return }
        dsp_set_surround3d_speakers(h, frontL, frontR, sideL, sideR, surroundL, surroundR)
    }
}

// MARK: - Live stems

/// Flutter side of the live-stem engine (HypeDSP/src/stems). The engine
/// separates ahead of each playhead on its own native thread; the audio taps
/// (HypeAudioTap.m) mix the result. Model loading and the speed test take
/// seconds, so they run off the main thread and answer on it.
final class StemsBridge: NSObject, FlutterStreamHandler {
    static let shared = StemsBridge()

    // Model loading runs here; ONNX Runtime's compute threads start from it.
    private let queue = DispatchQueue(label: "hype.stems.control", qos: .utility)
    private var eventSink: FlutterEventSink?
    private var attached = false

    /// Call once the Flutter engine's messenger exists.
    func attach(messenger: FlutterBinaryMessenger) {
        guard !attached else { return }
        attached = true
        let fm = FileManager.default
        let cache = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("stems", isDirectory: true)
        // Decoded audio from an earlier run is useless now.
        try? fm.removeItem(at: cache)
        try? fm.createDirectory(at: cache, withIntermediateDirectories: true)
        cache.path.withCString { dsp_stems_init($0) }
        dsp_stems_set_status_callback({ json, _ in
            guard let json = json else { return }
            let text = String(cString: json)
            DispatchQueue.main.async { StemsBridge.shared.emit(text) }
        }, nil)
        FlutterEventChannel(name: "eq_app/stems_events", binaryMessenger: messenger)
            .setStreamHandler(self)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "stemsLoadModel":
            let dir = args?["dir"] as? String ?? ""
            queue.async {
                var err = [CChar](repeating: 0, count: 512)
                let ok = dir.withCString { dsp_stems_load_model($0, &err, Int32(err.count)) }
                if !ok { NSLog("HypeStems: model load failed: %@", String(cString: err)) }
                DispatchQueue.main.async { result(ok) }
            }
        case "stemsUnloadModel":
            queue.async { dsp_stems_unload_model() }
            result(nil)
        case "stemsBenchmark":
            queue.async {
                var buf = [CChar](repeating: 0, count: 1024)
                dsp_stems_benchmark(&buf, Int32(buf.count))
                let map = StemsBridge.decode(String(cString: buf))
                DispatchQueue.main.async { result(map) }
            }
        case "stemsSetArmed":
            dsp_stems_set_armed(args?["armed"] as? Bool ?? false)
            result(nil)
        case "stemsSetLevels":
            dsp_stems_set_levels(StemsBridge.level(args?["vocals"]),
                                 StemsBridge.level(args?["drums"]),
                                 StemsBridge.level(args?["instruments"]))
            result(nil)
        case "stemsProvideStream":
            if let url = args?["url"] as? String, let path = args?["path"] as? String {
                dsp_stems_provide_stream(url, URL(fileURLWithPath: path).absoluteString)
            }
            result(nil)
        case "stemsGetStatus":
            result(StemsBridge.decode(StemsBridge.statusJson()))
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        events(StemsBridge.decode(StemsBridge.statusJson()))
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    // MARK: Helpers

    private func emit(_ json: String) {
        eventSink?(StemsBridge.decode(json))
    }

    private static func statusJson() -> String {
        var buf = [CChar](repeating: 0, count: 2048)
        dsp_stems_status_json(&buf, Int32(buf.count))
        return String(cString: buf)
    }

    private static func decode(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return map
    }

    private static func level(_ value: Any?) -> Float {
        if let d = value as? Double { return Float(d) }
        if let n = value as? NSNumber { return n.floatValue }
        return 1.0
    }
}
