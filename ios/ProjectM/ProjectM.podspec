Pod::Spec.new do |s|
  s.name             = 'ProjectM'
  s.version          = '4.1.2'
  s.summary          = 'projectM MilkDrop visualizer for iOS'
  s.homepage         = 'https://github.com/projectM-visualizer/projectm'
  s.license          = { :type => 'LGPL-2.1' }
  s.author           = 'projectM Team'
  s.source           = { :path => '.' }
  s.ios.deployment_target = '15.0'

  s.vendored_frameworks = 'lib/projectM.xcframework'
  s.public_header_files = 'include/projectM-4/*.h'
  s.source_files = 'include/**/*.h'
  s.header_mappings_dir = 'include'

  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/include"',
    'OTHER_LDFLAGS' => '-lc++',
  }

  s.user_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '"$(PODS_ROOT)/ProjectM/include"',
  }

  s.frameworks = 'OpenGLES'
  s.libraries = 'c++'
end
