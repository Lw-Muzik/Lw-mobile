cmake_minimum_required(VERSION 3.22.1)
project("eq_app")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -ffast-math")

add_library(${CMAKE_PROJECT_NAME} SHARED
    eq_app.cpp
    fdn_reverb.cpp
    room_dsp_engine.cpp
    jni_bridge.cpp)

target_link_libraries(${CMAKE_PROJECT_NAME}
    android
    log)
