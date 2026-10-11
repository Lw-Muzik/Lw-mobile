// JNI for x.a.zix.StemEngineBridge — the stem engine's control surface.
// Per-player tap events live in jni_bridge.cpp (RoomEffectsProcessor).

#include "ndk_pcm_source.h"
#include "stems/stem_engine.h"

#include <android/log.h>
#include <jni.h>
#include <unistd.h>

#include <cstdio>
#include <memory>
#include <string>
#include <vector>

#define STEMS_LOG_TAG "HypeStems"
#define SLOGI(...) __android_log_print(ANDROID_LOG_INFO, STEMS_LOG_TAG, __VA_ARGS__)

using hype::stems::StemEngine;
using hype::stems::StemStatus;

namespace {

JavaVM* gVm = nullptr;
jclass gBridge = nullptr;
jmethodID gOnStatus = nullptr;

std::string str(JNIEnv* env, jstring s) {
    if (!s) return std::string();
    const char* c = env->GetStringUTFChars(s, nullptr);
    std::string out(c ? c : "");
    if (c) env->ReleaseStringUTFChars(s, c);
    return out;
}

// The engine's worker thread lives as long as the process: attach it once
// and never detach.
JNIEnv* workerEnv() {
    if (!gVm) return nullptr;
    JNIEnv* env = nullptr;
    if (gVm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK) return env;
    JavaVMAttachArgs args{JNI_VERSION_1_6, "HypeStemsWorker", nullptr};
    if (gVm->AttachCurrentThread(&env, &args) != JNI_OK) return nullptr;
    return env;
}

}  // namespace

extern "C" {

JNIEXPORT void JNICALL
Java_x_a_zix_StemEngineBridge_nativeInit(JNIEnv* env, jclass cls, jstring cacheDir) {
    env->GetJavaVM(&gVm);
    if (!gBridge) {
        gBridge = static_cast<jclass>(env->NewGlobalRef(cls));
        gOnStatus = env->GetStaticMethodID(cls, "onNativeStatus", "(Ljava/lang/String;)V");
    }
    StemEngine& engine = StemEngine::instance();
    engine.setCacheDir(str(env, cacheDir));
    engine.setStatusCallback([](const StemStatus& st) {
        JNIEnv* e = workerEnv();
        if (!e || !gBridge || !gOnStatus) return;
        jstring json = e->NewStringUTF(st.toJson().c_str());
        e->CallStaticVoidMethod(gBridge, gOnStatus, json);
        if (e->ExceptionCheck()) e->ExceptionClear();
        e->DeleteLocalRef(json);
    });
}

// Returns null on success, else the error.
JNIEXPORT jstring JNICALL
Java_x_a_zix_StemEngineBridge_nativeLoadModel(JNIEnv* env, jclass, jstring dir) {
    std::string error;
    if (StemEngine::instance().loadModel(str(env, dir), &error)) {
        SLOGI("stem model loaded");
        return nullptr;
    }
    SLOGI("stem model failed to load: %s", error.c_str());
    return env->NewStringUTF(error.empty() ? "load failed" : error.c_str());
}

JNIEXPORT void JNICALL
Java_x_a_zix_StemEngineBridge_nativeUnloadModel(JNIEnv*, jclass) {
    StemEngine::instance().unloadModel();
}

// {"ok":bool,"rtf":double,"millis":int,"error":string}
JNIEXPORT jstring JNICALL
Java_x_a_zix_StemEngineBridge_nativeBenchmark(JNIEnv* env, jclass) {
    const StemEngine::Benchmark b = StemEngine::instance().benchmark();
    SLOGI("stem benchmark ok=%d rtf=%.3f millis=%d %s", b.ok, b.rtf, b.millis, b.error.c_str());
    const std::string err = hype::stems::jsonEscape(b.error);
    char head[96];
    std::snprintf(head, sizeof head, "{\"ok\":%s,\"rtf\":%.4f,\"millis\":%d,\"error\":\"",
                  b.ok ? "true" : "false", b.rtf, b.millis);
    return env->NewStringUTF((std::string(head) + err + "\"}").c_str());
}

JNIEXPORT void JNICALL
Java_x_a_zix_StemEngineBridge_nativeSetArmed(JNIEnv*, jclass, jboolean armed) {
    StemEngine::instance().setArmed(armed == JNI_TRUE);
}

JNIEXPORT void JNICALL
Java_x_a_zix_StemEngineBridge_nativeSetLevels(JNIEnv*, jclass, jfloat vocals, jfloat drums, jfloat instruments) {
    StemEngine::instance().setLevels(vocals, drums, instruments);
}

// A local copy of a streamed track, downloaded by the app (see provideSource).
JNIEXPORT void JNICALL
Java_x_a_zix_StemEngineBridge_nativeProvideSource(JNIEnv* env, jclass, jstring key, jstring path) {
    const std::string p = str(env, path);
    if (p.empty()) return;
    StemEngine::instance().provideSource(str(env, key),
                                         [p] { return hype::stems::createNdkPcmSource(p, -1); });
}

// `path` for local files, or `fd` (>= 0, ownership passes here) for content
// URIs; a non-empty `reason` marks the track unavailable.
JNIEXPORT jint JNICALL
Java_x_a_zix_StemEngineBridge_nativeRegisterTrack(JNIEnv* env, jclass, jstring key, jstring path,
                                                  jint fd, jstring reason) {
    const std::string p = str(env, path);
    hype::stems::PcmSourceFactory factory;
    if (!p.empty()) {
        factory = [p] { return hype::stems::createNdkPcmSource(p, -1); };
    } else if (fd >= 0) {
        // Each decode attempt gets its own dup; the original closes with the
        // last copy of the factory.
        std::shared_ptr<int> owned(new int(fd), [](int* f) {
            ::close(*f);
            delete f;
        });
        factory = [owned] {
            const int d = ::dup(*owned);
            return hype::stems::createNdkPcmSource(std::string(), d);
        };
    }
    return static_cast<jint>(StemEngine::instance().registerTrack(str(env, key), factory, str(env, reason)));
}

JNIEXPORT jstring JNICALL
Java_x_a_zix_StemEngineBridge_nativeStatusJson(JNIEnv* env, jclass) {
    return env->NewStringUTF(StemEngine::instance().status().toJson().c_str());
}

}  // extern "C"
