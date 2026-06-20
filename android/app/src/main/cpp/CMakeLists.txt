cmake_minimum_required(VERSION 3.22.1)
project("eq_app")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -ffast-math")

add_library(${CMAKE_PROJECT_NAME} SHARED
    eq_app.cpp
    fdn_reverb.cpp
    room_dsp_engine.cpp
    jni_bridge.cpp
    projectm_bridge.cpp
    chromaprint_jni.cpp)

# Prebuilt projectM-4 shared library
add_library(projectM-4 SHARED IMPORTED)
set_target_properties(projectM-4 PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libprojectM-4.so)

# Include paths for projectM headers
target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE
    ${CMAKE_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/projectm-include)

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
    ${GLES3_LIB}
    ${EGL_LIB})

# 16 KB page-size alignment for libeq_app.so — required for Android 15+ / devices
# with 16 KB memory pages (Play Store requirement for new uploads). NDK r28
# links with max-page-size=16384 by default; we set it explicitly so the build
# is correct regardless of the NDK in use.
target_link_options(${CMAKE_PROJECT_NAME} PRIVATE
    "-Wl,-z,max-page-size=16384")
