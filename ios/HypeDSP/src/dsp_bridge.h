// C bridge for RoomDSPEngine — called from Swift via bridging header.
// All functions are plain C so they can be used from both Objective-C and Swift.

#ifndef DSP_BRIDGE_H
#define DSP_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Lifecycle
void* dsp_create(int sampleRate, int channels);
void  dsp_destroy(void* handle);
void  dsp_reinit(void* handle, int sampleRate, int channels);
void  dsp_reset(void* handle);

// Process interleaved stereo float PCM in-place
void  dsp_process_float(void* handle, float* buffer, int numFrames);

// EQ
void  dsp_set_eq_enabled(void* handle, bool enabled);
void  dsp_set_preamp_gain(void* handle, float dB);
float dsp_get_preamp_gain(void* handle);
void  dsp_set_graphic_band_gain(void* handle, int band, float dB);
void  dsp_set_graphic_all_bands(void* handle, const float* gains, int count);
void  dsp_set_parametric_band(void* handle, int band, float freq, float gainDb,
                               float q, int filterType, bool enabled);
void  dsp_set_parametric_all_bands(void* handle, const float* freqs,
                                    const float* gains, const float* qs, int count);

// Speaker correction EQ
void  dsp_set_speaker_eq_enabled(void* handle, bool enabled);
void  dsp_set_speaker_eq_band(void* handle, int band, float freq, float gainDb,
                               float q, int filterType, bool enabled);
void  dsp_clear_speaker_eq(void* handle);

// Tone controls
void  dsp_set_tone_enabled(void* handle, bool enabled);
void  dsp_set_bass_gain(void* handle, float dB);
void  dsp_set_bass_freq(void* handle, float hz);
void  dsp_set_bass_q(void* handle, float q);
void  dsp_set_treble_gain(void* handle, float dB);
void  dsp_set_treble_freq(void* handle, float hz);
void  dsp_set_treble_q(void* handle, float q);

// Output limiter
void  dsp_set_limiter_enabled(void* handle, bool enabled);
void  dsp_set_limiter_ceiling(void* handle, float v);
void  dsp_set_limiter_release(void* handle, float ms);
void  dsp_set_limiter_knee(void* handle, float dB);

// MBC
void  dsp_set_mbc_enabled(void* handle, bool enabled);
bool  dsp_is_mbc_enabled(void* handle);
void  dsp_set_mbc_pre_gain(void* handle, float dB);
void  dsp_set_mbc_noise_gate(void* handle, float dB);
void  dsp_set_mbc_knee_width(void* handle, float dB);
void  dsp_set_mbc_expander_ratio(void* handle, float ratio);
void  dsp_set_mbc_threshold(void* handle, float dB);
void  dsp_set_mbc_ratio(void* handle, float ratio);
void  dsp_set_mbc_attack_time(void* handle, float ms);
void  dsp_set_mbc_release_time(void* handle, float ms);
void  dsp_set_mbc_post_gain(void* handle, float dB);

// Reverb
void  dsp_set_reverb_enabled(void* handle, bool enabled);
void  dsp_set_room_size(void* handle, float v);
void  dsp_set_decay(void* handle, float v);
void  dsp_set_damping(void* handle, float v);
void  dsp_set_pre_delay(void* handle, float ms);
void  dsp_set_diffusion(void* handle, float v);
void  dsp_set_reverb_wet_dry(void* handle, float v);

// Stereo expander
void  dsp_set_stereo_expand_enabled(void* handle, bool enabled);
void  dsp_set_stereo_width(void* handle, float width);

// Crossfeed
void  dsp_set_crossfeed_enabled(void* handle, bool enabled);
void  dsp_set_crossfeed_params(void* handle, float cutoffHz, float feedLevelDb);

// Stem mixer
void  dsp_set_stem_mode_active(void* handle, bool active);
bool  dsp_load_stems(void* handle, const char* vocals, const char* drums,
                     const char* bass, const char* other);
void  dsp_unload_stems(void* handle);
void  dsp_set_stem_volume(void* handle, int stem, float vol);
void  dsp_set_stem_mute(void* handle, int stem, bool muted);
void  dsp_set_stem_solo(void* handle, int stem, bool soloed);
void  dsp_stem_seek(void* handle, int64_t samplePos);

#ifdef __cplusplus
}
#endif

#endif // DSP_BRIDGE_H
