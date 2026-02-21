#include <jni.h>
#include <android/log.h>
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include "projectM-4/projectM.h"

#define LOG_TAG "ProjectMBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern "C" {

JNIEXPORT jlong JNICALL
Java_x_a_zix_ProjectMRenderer_nativeCreate(JNIEnv* env, jobject) {
    projectm_handle handle = projectm_create();
    if (!handle) {
        LOGE("projectm_create() returned NULL — is OpenGL context current?");
        return 0;
    }
    LOGI("projectM instance created");
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT void JNICALL
Java_x_a_zix_ProjectMRenderer_nativeDestroy(JNIEnv* env, jobject, jlong handle) {
    auto* pm = reinterpret_cast<projectm_handle>(handle);
    if (pm) {
        projectm_destroy(pm);
        LOGI("projectM instance destroyed");
    }
}

JNIEXPORT void JNICALL
Java_x_a_zix_ProjectMRenderer_nativeSetWindowSize(JNIEnv* env, jobject, jlong handle,
                                                   jint width, jint height) {
    auto* pm = reinterpret_cast<projectm_handle>(handle);
    if (pm) {
        projectm_set_window_size(pm, (size_t)width, (size_t)height);
        LOGI("Window size set: %dx%d", width, height);
    }
}

JNIEXPORT void JNICALL
Java_x_a_zix_ProjectMRenderer_nativeRenderFrame(JNIEnv* env, jobject, jlong handle) {
    auto* pm = reinterpret_cast<projectm_handle>(handle);
    if (pm) {
        projectm_opengl_render_frame(pm);
    }
}

JNIEXPORT void JNICALL
Java_x_a_zix_ProjectMRenderer_nativeAddPcmFloat(JNIEnv* env, jobject, jlong handle,
                                                 jfloatArray samples) {
    auto* pm = reinterpret_cast<projectm_handle>(handle);
    if (!pm || !samples) return;

    jsize len = env->GetArrayLength(samples);
    jfloat* data = env->GetFloatArrayElements(samples, nullptr);
    if (data) {
        // Interleaved stereo: count = total_samples / 2 (per channel)
        unsigned int count = (unsigned int)(len / 2);
        projectm_pcm_add_float(pm, data, count, PROJECTM_STEREO);
        env->ReleaseFloatArrayElements(samples, data, JNI_ABORT);
    }
}

JNIEXPORT void JNICALL
Java_x_a_zix_ProjectMRenderer_nativeLoadPresetFile(JNIEnv* env, jobject, jlong handle,
                                                    jstring path, jboolean smooth) {
    auto* pm = reinterpret_cast<projectm_handle>(handle);
    if (!pm || !path) return;

    const char* pathStr = env->GetStringUTFChars(path, nullptr);
    projectm_load_preset_file(pm, pathStr, (bool)smooth);
    LOGI("Loaded preset: %s", pathStr);
    env->ReleaseStringUTFChars(path, pathStr);
}

JNIEXPORT void JNICALL
Java_x_a_zix_ProjectMRenderer_nativeLoadPresetData(JNIEnv* env, jobject, jlong handle,
                                                    jstring data, jboolean smooth) {
    auto* pm = reinterpret_cast<projectm_handle>(handle);
    if (!pm || !data) return;

    const char* dataStr = env->GetStringUTFChars(data, nullptr);
    projectm_load_preset_data(pm, dataStr, (bool)smooth);
    env->ReleaseStringUTFChars(data, dataStr);
}

JNIEXPORT void JNICALL
Java_x_a_zix_ProjectMRenderer_nativeSetBeatSensitivity(JNIEnv* env, jobject, jlong handle,
                                                        jfloat sensitivity) {
    auto* pm = reinterpret_cast<projectm_handle>(handle);
    if (pm) projectm_set_beat_sensitivity(pm, sensitivity);
}

JNIEXPORT void JNICALL
Java_x_a_zix_ProjectMRenderer_nativeSetPresetDuration(JNIEnv* env, jobject, jlong handle,
                                                       jdouble seconds) {
    auto* pm = reinterpret_cast<projectm_handle>(handle);
    if (pm) projectm_set_preset_duration(pm, seconds);
}

JNIEXPORT void JNICALL
Java_x_a_zix_ProjectMRenderer_nativeSetPresetLocked(JNIEnv* env, jobject, jlong handle,
                                                     jboolean locked) {
    auto* pm = reinterpret_cast<projectm_handle>(handle);
    if (pm) projectm_set_preset_locked(pm, (bool)locked);
}

JNIEXPORT void JNICALL
Java_x_a_zix_ProjectMRenderer_nativeSetFps(JNIEnv* env, jobject, jlong handle, jint fps) {
    auto* pm = reinterpret_cast<projectm_handle>(handle);
    if (pm) projectm_set_fps(pm, fps);
}

JNIEXPORT void JNICALL
Java_x_a_zix_ProjectMRenderer_nativeSetHardCutEnabled(JNIEnv* env, jobject, jlong handle,
                                                       jboolean enabled) {
    auto* pm = reinterpret_cast<projectm_handle>(handle);
    if (pm) projectm_set_hard_cut_enabled(pm, (bool)enabled);
}

JNIEXPORT void JNICALL
Java_x_a_zix_ProjectMRenderer_nativeSetSoftCutDuration(JNIEnv* env, jobject, jlong handle,
                                                        jdouble seconds) {
    auto* pm = reinterpret_cast<projectm_handle>(handle);
    if (pm) projectm_set_soft_cut_duration(pm, seconds);
}

JNIEXPORT void JNICALL
Java_x_a_zix_ProjectMRenderer_nativeSetMeshSize(JNIEnv* env, jobject, jlong handle,
                                                 jint width, jint height) {
    auto* pm = reinterpret_cast<projectm_handle>(handle);
    if (pm) projectm_set_mesh_size(pm, (size_t)width, (size_t)height);
}

JNIEXPORT void JNICALL
Java_x_a_zix_ProjectMRenderer_nativeSetAspectCorrection(JNIEnv* env, jobject, jlong handle,
                                                         jboolean enabled) {
    auto* pm = reinterpret_cast<projectm_handle>(handle);
    if (pm) projectm_set_aspect_correction(pm, (bool)enabled);
}

JNIEXPORT void JNICALL
Java_x_a_zix_ProjectMRenderer_nativeSetTextureSearchPaths(JNIEnv* env, jobject, jlong handle,
                                                           jobjectArray paths) {
    auto* pm = reinterpret_cast<projectm_handle>(handle);
    if (!pm || !paths) return;

    int count = env->GetArrayLength(paths);
    const char** pathArray = new const char*[count];
    for (int i = 0; i < count; i++) {
        jstring str = (jstring)env->GetObjectArrayElement(paths, i);
        pathArray[i] = env->GetStringUTFChars(str, nullptr);
    }

    projectm_set_texture_search_paths(pm, pathArray, (size_t)count);

    for (int i = 0; i < count; i++) {
        jstring str = (jstring)env->GetObjectArrayElement(paths, i);
        env->ReleaseStringUTFChars(str, pathArray[i]);
    }
    delete[] pathArray;
}

} // extern "C"
