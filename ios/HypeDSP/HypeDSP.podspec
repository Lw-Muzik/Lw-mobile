Pod::Spec.new do |s|
  s.name             = 'HypeDSP'
  s.version          = '1.0.0'
  s.summary          = 'Custom C++ DSP engine for Hype Muzik'
  s.homepage         = 'https://github.com/example/hype'
  s.license          = { :type => 'Proprietary' }
  s.author           = 'Hype'
  s.source           = { :path => '.' }
  s.ios.deployment_target = '15.1'

  # src/stems is the live-stem engine, copied from android/app/src/main/cpp/stems
  # by tool/sync_stems_native.sh; src/stems_ios is its AVFoundation decoder.
  s.source_files = 'src/**/*.{h,cpp,mm}', 'include/**/*.h'
  s.public_header_files = 'include/**/*.h'

  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS' => '-O3 -ffast-math',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/src"',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited)',
  }

  s.user_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
  }

  s.libraries = 'c++'
  s.frameworks = 'AVFoundation', 'CoreMedia', 'AudioToolbox'

  # ONNX Runtime runs the Spleeter stem nets. Its pod vendors a static
  # xcframework, and CocoaPods refuses a dynamic framework that depends on a
  # static one — so HypeDSP is a static framework too (the bridging header's
  # #import <HypeDSP/dsp_bridge.h> is unaffected).
  s.dependency 'onnxruntime-c', '1.30.0'
  s.static_framework = true
end
