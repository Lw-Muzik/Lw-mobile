Pod::Spec.new do |s|
  s.name             = 'HypeDSP'
  s.version          = '1.0.0'
  s.summary          = 'Custom C++ DSP engine for Hype Muzik'
  s.homepage         = 'https://github.com/example/hype'
  s.license          = { :type => 'Proprietary' }
  s.author           = 'Hype'
  s.source           = { :path => '.' }
  s.ios.deployment_target = '15.0'

  s.source_files = 'src/**/*.{h,cpp}', 'include/**/*.h'
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
end
