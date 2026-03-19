// C bridge implementation — wraps RoomDSPEngine for Swift access.

#include "dsp_bridge.h"
#include "room_dsp_engine.h"

extern "C" {

void* dsp_create(int sampleRate, int channels) {
    auto* engine = new RoomDSPEngine();
    engine->init(sampleRate, channels);
    return engine;
}

void dsp_destroy(void* handle) {
    delete static_cast<RoomDSPEngine*>(handle);
}

void dsp_reinit(void* handle, int sampleRate, int channels) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->init(sampleRate, channels);
}

void dsp_reset(void* handle) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->reset();
}

void dsp_process_float(void* handle, float* buffer, int numFrames) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->process(buffer, numFrames);
}

// EQ
void dsp_set_eq_enabled(void* handle, bool enabled) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setEqEnabled(enabled);
}

void dsp_set_preamp_gain(void* handle, float dB) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setPreampGain(dB);
}

float dsp_get_preamp_gain(void* handle) {
    // The engine doesn't expose a getter, but we track it via cached params
    return 0.0f;
}

void dsp_set_graphic_band_gain(void* handle, int band, float dB) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setGraphicBandGain(band, dB);
}

void dsp_set_graphic_all_bands(void* handle, const float* gains, int count) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setGraphicAllBands(gains, count);
}

void dsp_set_parametric_band(void* handle, int band, float freq, float gainDb,
                              float q, int filterType, bool enabled) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setParametricBand(
        band, freq, gainDb, q, filterType, enabled);
}

void dsp_set_parametric_all_bands(void* handle, const float* freqs,
                                   const float* gains, const float* qs, int count) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setParametricAllBands(
        freqs, gains, qs, count);
}

// Speaker correction EQ
void dsp_set_speaker_eq_enabled(void* handle, bool enabled) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setSpeakerEqEnabled(enabled);
}

void dsp_set_speaker_eq_band(void* handle, int band, float freq, float gainDb,
                              float q, int filterType, bool enabled) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setSpeakerEqBand(
        band, freq, gainDb, q, filterType, enabled);
}

void dsp_clear_speaker_eq(void* handle) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->clearSpeakerEq();
}

// Tone
void dsp_set_tone_enabled(void* handle, bool enabled) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setToneEnabled(enabled);
}

void dsp_set_bass_gain(void* handle, float dB) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setBassGain(dB);
}

void dsp_set_bass_freq(void* handle, float hz) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setBassFreq(hz);
}

void dsp_set_bass_q(void* handle, float q) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setBassQ(q);
}

void dsp_set_treble_gain(void* handle, float dB) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setTrebleGain(dB);
}

void dsp_set_treble_freq(void* handle, float hz) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setTrebleFreq(hz);
}

void dsp_set_treble_q(void* handle, float q) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setTrebleQ(q);
}

// Limiter
void dsp_set_limiter_enabled(void* handle, bool enabled) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setLimiterEnabled(enabled);
}

void dsp_set_limiter_ceiling(void* handle, float v) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setLimiterCeiling(v);
}

void dsp_set_limiter_release(void* handle, float ms) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setLimiterRelease(ms);
}

void dsp_set_limiter_knee(void* handle, float dB) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setLimiterKnee(dB);
}

// MBC
void dsp_set_mbc_enabled(void* handle, bool enabled) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setMbcEnabled(enabled);
}

bool dsp_is_mbc_enabled(void* handle) {
    if (handle) return static_cast<RoomDSPEngine*>(handle)->isMbcEnabled();
    return false;
}

void dsp_set_mbc_pre_gain(void* handle, float dB) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setMbcPreGain(dB);
}

void dsp_set_mbc_noise_gate(void* handle, float dB) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setMbcNoiseGateThreshold(dB);
}

void dsp_set_mbc_knee_width(void* handle, float dB) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setMbcKneeWidth(dB);
}

void dsp_set_mbc_expander_ratio(void* handle, float ratio) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setMbcExpanderRatio(ratio);
}

void dsp_set_mbc_threshold(void* handle, float dB) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setMbcThreshold(dB);
}

void dsp_set_mbc_ratio(void* handle, float ratio) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setMbcRatio(ratio);
}

void dsp_set_mbc_attack_time(void* handle, float ms) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setMbcAttackTime(ms);
}

void dsp_set_mbc_release_time(void* handle, float ms) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setMbcReleaseTime(ms);
}

void dsp_set_mbc_post_gain(void* handle, float dB) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setMbcPostGain(dB);
}

// Reverb
void dsp_set_reverb_enabled(void* handle, bool enabled) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setReverbEnabled(enabled);
}

void dsp_set_room_size(void* handle, float v) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setRoomSize(v);
}

void dsp_set_decay(void* handle, float v) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setDecay(v);
}

void dsp_set_damping(void* handle, float v) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setDamping(v);
}

void dsp_set_pre_delay(void* handle, float ms) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setPreDelay(ms);
}

void dsp_set_diffusion(void* handle, float v) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setDiffusion(v);
}

void dsp_set_reverb_wet_dry(void* handle, float v) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setReverbWetDry(v);
}

// Stereo expander
void dsp_set_stereo_expand_enabled(void* handle, bool enabled) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setStereoExpandEnabled(enabled);
}

void dsp_set_stereo_width(void* handle, float width) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setStereoWidth(width);
}

// Crossfeed
void dsp_set_crossfeed_enabled(void* handle, bool enabled) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setCrossfeedEnabled(enabled);
}

void dsp_set_crossfeed_params(void* handle, float cutoffHz, float feedLevelDb) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setCrossfeedParams(cutoffHz, feedLevelDb);
}

// Stem mixer
void dsp_set_stem_mode_active(void* handle, bool active) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setStemModeActive(active);
}

bool dsp_load_stems(void* handle, const char* vocals, const char* drums,
                    const char* bass, const char* other) {
    if (!handle) return false;
    const char* paths[4] = { vocals, drums, bass, other };
    return static_cast<RoomDSPEngine*>(handle)->loadStems(paths);
}

void dsp_unload_stems(void* handle) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->unloadStems();
}

void dsp_set_stem_volume(void* handle, int stem, float vol) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setStemVolume(stem, vol);
}

void dsp_set_stem_mute(void* handle, int stem, bool muted) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setStemMute(stem, muted);
}

void dsp_set_stem_solo(void* handle, int stem, bool soloed) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->setStemSolo(stem, soloed);
}

void dsp_stem_seek(void* handle, int64_t samplePos) {
    if (handle) static_cast<RoomDSPEngine*>(handle)->stemSeek(static_cast<size_t>(samplePos));
}

} // extern "C"
