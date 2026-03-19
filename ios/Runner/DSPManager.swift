import Foundation
import AVFoundation

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

    // MARK: - Stem Mixer

    func setStemModeActive(_ active: Bool) {
        guard let h = handle else { return }
        dsp_set_stem_mode_active(h, active)
    }

    func loadStems(vocals: String, drums: String, bass: String, other: String) -> Bool {
        guard let h = handle else { return false }
        return vocals.withCString { v in
            drums.withCString { d in
                bass.withCString { b in
                    other.withCString { o in
                        dsp_load_stems(h, v, d, b, o)
                    }
                }
            }
        }
    }

    func unloadStems() {
        guard let h = handle else { return }
        dsp_unload_stems(h)
    }

    func setStemVolume(stem: Int, volume: Float) {
        guard let h = handle else { return }
        dsp_set_stem_volume(h, Int32(stem), volume)
    }

    func setStemMute(stem: Int, muted: Bool) {
        guard let h = handle else { return }
        dsp_set_stem_mute(h, Int32(stem), muted)
    }

    func setStemSolo(stem: Int, soloed: Bool) {
        guard let h = handle else { return }
        dsp_set_stem_solo(h, Int32(stem), soloed)
    }

    func stemSeek(samplePosition: Int64) {
        guard let h = handle else { return }
        dsp_stem_seek(h, samplePosition)
    }
}
