# Hype project notes

## iOS build
- `ios/Podfile` sets the app's iOS deployment target and C++ build settings.
- Do not define `SWIFT_PACKAGE` for the `flutter_foreground_task` CocoaPods target. Version 11.x ships a CocoaPods-visible Objective-C `FlutterForegroundTaskPlugin` in `Classes/FlutterForegroundTaskPlugin.{h,m}`; enabling the SPM bridge in `Sources/.../FlutterForegroundTaskPluginSPMBridge.swift` also declares that same class and fails with a duplicate interface.
- When changing plugin-specific Podfile workarounds, verify against the resolved plugin version under `.pub-cache` and inspect its podspec source inclusion.
- `ios/Runner.xcodeproj` includes a FlutterFire Crashlytics symbol-upload build phase. Xcode PATH includes `$PUB_CACHE/bin` and `$HOME/.pub-cache/bin`, but the build fails with `flutterfire: command not found` unless `flutterfire_cli` is activated (`dart pub global activate flutterfire_cli`). An unsigned IPA archive succeeded after installing CLI 1.4.1.
