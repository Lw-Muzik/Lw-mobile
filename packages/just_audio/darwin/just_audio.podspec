#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'just_audio'
  s.version          = '0.0.1'
  s.summary          = 'Flutter audio player'
  s.description      = <<-DESC
A flutter plugin for playing audio.
                       DESC
  s.homepage         = 'https://github.com/ryanheise/just_audio'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'just_audio/Sources/just_audio/**/*.{h,m}'
  s.public_header_files = 'just_audio/Sources/just_audio/include/**/*.h'
  s.ios.dependency 'Flutter'
  # AVKit is what drives picture-in-picture. It is iOS-only: macOS has its own
  # PiP story and this plugin does not implement it there.
  s.ios.frameworks = 'AVKit', 'AVFoundation'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '12.0'
  s.osx.deployment_target = '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
