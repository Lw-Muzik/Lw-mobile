#include <jni.h>
#include <android/log.h>
#include "room_dsp_engine.h"

#define LOG_TAG "HypeDSP"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern "C" {

JNIEXPORT jlong JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeCreate(JNIEnv* env, jobject, jint sampleRate, jint channels) {
    auto* engine = new RoomDSPEngine();
    engine->init(sampleRate, channels);
    LOGI("DSP engine created: %dHz, %dch", sampleRate, channels);
    return reinterpret_cast<jlong>(engine);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeDestroy(JNIEnv* env, jobject, jlong handle) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    delete engine;
    LOGI("DSP engine destroyed");
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeReset(JNIEnv* env, jobject, jlong handle) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->reset();
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeReinit(JNIEnv* env, jobject, jlong handle, jint sampleRate, jint channels) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->init(sampleRate, channels);
}

// --- Process ---

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeProcessFloat(JNIEnv* env, jobject, jlong handle,
                                                       jobject buffer, jint numFrames) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (!engine) return;

    auto* data = static_cast<float*>(env->GetDirectBufferAddress(buffer));
    if (!data) return;

    engine->process(data, numFrames);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeProcessShort(JNIEnv* env, jobject, jlong handle,
                                                       jobject buffer, jint numFrames) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (!engine) return;

    auto* data = static_cast<short*>(env->GetDirectBufferAddress(buffer));
    if (!data) return;

    int totalSamples = numFrames * 2; // stereo
    constexpr int STACK_LIMIT = 4096;
    float stackBuf[STACK_LIMIT];
    float* floatBuf;
    float* heapBuf = nullptr;

    if (totalSamples <= STACK_LIMIT) {
        floatBuf = stackBuf;
    } else {
        heapBuf = new float[totalSamples];
        floatBuf = heapBuf;
    }

    // Convert short to float (-1.0 to 1.0)
    constexpr float toFloat = 1.0f / 32768.0f;
    for (int i = 0; i < totalSamples; i++) {
        floatBuf[i] = data[i] * toFloat;
    }

    engine->process(floatBuf, numFrames);

    // Convert float back to short with clipping
    for (int i = 0; i < totalSamples; i++) {
        float v = floatBuf[i] * 32768.0f;
        if (v > 32767.0f) v = 32767.0f;
        if (v < -32768.0f) v = -32768.0f;
        data[i] = static_cast<short>(v);
    }

    delete[] heapBuf;
}

// --- Reverb controls ---

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetReverbEnabled(JNIEnv*, jobject, jlong handle, jboolean enabled) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setReverbEnabled(enabled);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetRoomSize(JNIEnv*, jobject, jlong handle, jfloat v) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setRoomSize(v);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetDecay(JNIEnv*, jobject, jlong handle, jfloat v) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setDecay(v);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetDamping(JNIEnv*, jobject, jlong handle, jfloat v) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setDamping(v);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetPreDelay(JNIEnv*, jobject, jlong handle, jfloat ms) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setPreDelay(ms);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetDiffusion(JNIEnv*, jobject, jlong handle, jfloat v) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setDiffusion(v);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetReverbWetDry(JNIEnv*, jobject, jlong handle, jfloat v) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setReverbWetDry(v);
}

// --- Stereo expander controls ---

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetStereoExpandEnabled(JNIEnv*, jobject, jlong handle, jboolean enabled) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setStereoExpandEnabled(enabled);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetStereoWidth(JNIEnv*, jobject, jlong handle, jfloat width) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setStereoWidth(width);
}

// --- Crossfeed controls ---

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetCrossfeedEnabled(JNIEnv*, jobject, jlong handle, jboolean enabled) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setCrossfeedEnabled(enabled);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetCrossfeedParams(JNIEnv*, jobject, jlong handle,
                                                            jfloat cutoffHz, jfloat feedLevelDb) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setCrossfeedParams(cutoffHz, feedLevelDb);
}

// --- EQ controls ---

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetEqEnabled(JNIEnv*, jobject, jlong handle, jboolean enabled) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setEqEnabled(enabled);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetPreampGain(JNIEnv*, jobject, jlong handle, jfloat dB) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setPreampGain(dB);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetGraphicBandGain(JNIEnv*, jobject, jlong handle,
                                                            jint band, jfloat dB) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setGraphicBandGain(band, dB);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetGraphicAllBands(JNIEnv* env, jobject, jlong handle,
                                                            jfloatArray gains) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (!engine) return;
    jfloat* data = env->GetFloatArrayElements(gains, nullptr);
    if (!data) return;
    int count = env->GetArrayLength(gains);
    engine->setGraphicAllBands(data, count);
    env->ReleaseFloatArrayElements(gains, data, JNI_ABORT);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetParametricBand(JNIEnv*, jobject, jlong handle,
                                                           jint band, jfloat freq, jfloat gainDb,
                                                           jfloat q, jint filterType, jboolean enabled) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setParametricBand(band, freq, gainDb, q, filterType, enabled);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetParametricAllBands(JNIEnv* env, jobject, jlong handle,
                                                               jfloatArray freqs, jfloatArray gains,
                                                               jfloatArray qs, jint count) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (!engine) return;
    jfloat* fData = env->GetFloatArrayElements(freqs, nullptr);
    jfloat* gData = env->GetFloatArrayElements(gains, nullptr);
    jfloat* qData = env->GetFloatArrayElements(qs, nullptr);
    if (fData && gData && qData) {
        engine->setParametricAllBands(fData, gData, qData, count);
    }
    if (fData) env->ReleaseFloatArrayElements(freqs, fData, JNI_ABORT);
    if (gData) env->ReleaseFloatArrayElements(gains, gData, JNI_ABORT);
    if (qData) env->ReleaseFloatArrayElements(qs, qData, JNI_ABORT);
}

// --- MBC controls ---

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetMbcEnabled(JNIEnv*, jobject, jlong handle, jboolean enabled) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setMbcEnabled(enabled);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetMbcPreGain(JNIEnv*, jobject, jlong handle, jfloat dB) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setMbcPreGain(dB);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetMbcNoiseGate(JNIEnv*, jobject, jlong handle, jfloat dB) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setMbcNoiseGateThreshold(dB);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetMbcKneeWidth(JNIEnv*, jobject, jlong handle, jfloat dB) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setMbcKneeWidth(dB);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetMbcExpanderRatio(JNIEnv*, jobject, jlong handle, jfloat ratio) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setMbcExpanderRatio(ratio);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetMbcThreshold(JNIEnv*, jobject, jlong handle, jfloat dB) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setMbcThreshold(dB);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetMbcRatio(JNIEnv*, jobject, jlong handle, jfloat ratio) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setMbcRatio(ratio);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetMbcAttackTime(JNIEnv*, jobject, jlong handle, jfloat ms) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setMbcAttackTime(ms);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetMbcReleaseTime(JNIEnv*, jobject, jlong handle, jfloat ms) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setMbcReleaseTime(ms);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetMbcPostGain(JNIEnv*, jobject, jlong handle, jfloat dB) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setMbcPostGain(dB);
}

// --- Tone controls (bass/treble) ---

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetToneEnabled(JNIEnv*, jobject, jlong handle, jboolean enabled) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setToneEnabled(enabled);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetBassGain(JNIEnv*, jobject, jlong handle, jfloat dB) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setBassGain(dB);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetBassFreq(JNIEnv*, jobject, jlong handle, jfloat hz) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setBassFreq(hz);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetBassQ(JNIEnv*, jobject, jlong handle, jfloat q) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setBassQ(q);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetTrebleGain(JNIEnv*, jobject, jlong handle, jfloat dB) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setTrebleGain(dB);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetTrebleFreq(JNIEnv*, jobject, jlong handle, jfloat hz) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setTrebleFreq(hz);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetTrebleQ(JNIEnv*, jobject, jlong handle, jfloat q) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setTrebleQ(q);
}

// --- Output limiter controls ---

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetLimiterEnabled(JNIEnv*, jobject, jlong handle, jboolean enabled) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setLimiterEnabled(enabled);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetLimiterCeiling(JNIEnv*, jobject, jlong handle, jfloat v) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setLimiterCeiling(v);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetLimiterRelease(JNIEnv*, jobject, jlong handle, jfloat ms) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setLimiterRelease(ms);
}

JNIEXPORT void JNICALL
Java_x_a_zix_RoomEffectsProcessor_nativeSetLimiterKnee(JNIEnv*, jobject, jlong handle, jfloat dB) {
    auto* engine = reinterpret_cast<RoomDSPEngine*>(handle);
    if (engine) engine->setLimiterKnee(dB);
}

} // extern "C"
