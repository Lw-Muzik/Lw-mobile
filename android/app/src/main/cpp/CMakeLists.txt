cmake_minimum_required(VERSION 3.22.1)
project("eq_app")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -ffast-math")

# Live stem separation: the engine in stems/ is shared with the iOS pod
# (ios/HypeDSP/src/stems, kept identical by tool/sync_stems_native.sh);
# stems_android/ is the NDK decoder and JNI.
file(GLOB STEMS_SOURCES
    ${CMAKE_SOURCE_DIR}/stems/*.cpp
    ${CMAKE_SOURCE_DIR}/stems_android/*.cpp)

add_library(${CMAKE_PROJECT_NAME} SHARED
    eq_app.cpp
    fdn_reverb.cpp
    room_dsp_engine.cpp
    jni_bridge.cpp
    projectm_bridge.cpp
    chromaprint_jni.cpp
    ${STEMS_SOURCES})

# Prebuilt projectM-4 shared library
add_library(projectM-4 SHARED IMPORTED)
set_target_properties(projectM-4 PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libprojectM-4.so)

# Include paths for projectM headers
target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE
    ${CMAKE_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/projectm-include)

# ONNX Runtime (headers and libraries extracted from the AAR by Gradle; see
# extractOnnxRuntime in app/build.gradle.kts).
if(NOT ORT_DIR)
    message(FATAL_ERROR "ORT_DIR not set — run the Gradle build (extractOnnxRuntime)")
endif()
add_library(onnxruntime SHARED IMPORTED)
set_target_properties(onnxruntime PROPERTIES
    IMPORTED_LOCATION ${ORT_DIR}/jni/${ANDROID_ABI}/libonnxruntime.so)
target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE ${ORT_DIR}/headers)

find_library(MEDIANDK_LIB mediandk)
find_library(GLES3_LIB GLESv3)
find_library(EGL_LIB EGL)

# Prebuilt Chromaprint shared library (audio fingerprinting)
add_library(chromaprint SHARED IMPORTED)
set_target_properties(chromaprint PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libchromaprint.so)

target_link_libraries(${CMAKE_PROJECT_NAME}
    android
    log
    projectM-4
    chromaprint
    onnxruntime
    ${MEDIANDK_LIB}
    ${GLES3_LIB}
    ${EGL_LIB})

# 16 KB page-size alignment for libeq_app.so — required for Android 15+ / devices
# with 16 KB memory pages (Play Store requirement for new uploads). NDK r28
# links with max-page-size=16384 by default; we set it explicitly so the build
# is correct regardless of the NDK in use.
target_link_options(${CMAKE_PROJECT_NAME} PRIVATE
    "-Wl,-z,max-page-size=16384")
