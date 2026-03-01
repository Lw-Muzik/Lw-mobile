#include <jni.h>
#include <cstdlib>
#include "chromaprint.h"

extern "C" {

JNIEXPORT jstring JNICALL
Java_x_a_zix_FingerprintEngine_nativeFingerprint(
    JNIEnv* env, jclass, jshortArray pcmData, jint sampleRate, jint channels)
{
    if (pcmData == nullptr) {
        return nullptr;
    }

    jint length = env->GetArrayLength(pcmData);
    if (length == 0) {
        return nullptr;
    }

    jshort* samples = env->GetShortArrayElements(pcmData, nullptr);
    if (samples == nullptr) {
        return nullptr;
    }

    ChromaprintContext* ctx = chromaprint_new(CHROMAPRINT_ALGORITHM_DEFAULT);
    if (ctx == nullptr) {
        env->ReleaseShortArrayElements(pcmData, samples, JNI_ABORT);
        return nullptr;
    }

    jstring result = nullptr;

    if (chromaprint_start(ctx, sampleRate, channels) &&
        chromaprint_feed(ctx, reinterpret_cast<const int16_t*>(samples), length) &&
        chromaprint_finish(ctx))
    {
        char* fingerprint = nullptr;
        if (chromaprint_get_fingerprint(ctx, &fingerprint) && fingerprint != nullptr) {
            result = env->NewStringUTF(fingerprint);
            chromaprint_dealloc(fingerprint);
        }
    }

    chromaprint_free(ctx);
    env->ReleaseShortArrayElements(pcmData, samples, JNI_ABORT);

    return result;
}

} // extern "C"
