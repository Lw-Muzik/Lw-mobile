# Flutter specific rules (v1 and v2 embedding)
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.embedding.android.** { *; }
-keep class io.flutter.embedding.engine.** { *; }

# Keep AndroidX and support library classes
-keep class androidx.** { *; }
-keep interface androidx.** { *; }
-dontwarn androidx.**
-keep class androidx.core.app.CoreComponentFactory { *; }

# Keep MainActivity and related classes
-keep class x.a.zix.MainActivity { *; }
-keep class x.a.zix.** { *; }

# Keep AudioService related classes
-keep class com.ryanheise.audioservice.** { *; }

# Keep all your custom equalizer classes
-keep class x.a.zix.AudioVisualizer { *; }
-keep class x.a.zix.BassEq { *; }
-keep class x.a.zix.LoudnessControl { *; }
-keep class x.a.zix.DvcController { *; }
-keep class x.a.zix.ReverbEngine { *; }
-keep class x.a.zix.RoomEffectsProcessor { *; }

# Keep classes used by Flutter method channels
-keepclassmembers class * {
  @io.flutter.plugin.common.MethodChannel.MethodCallHandler *;
}

# Ignore missing Google Play Core classes (they're optional)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Keep Google Play Core classes if present
-keep class com.google.android.play.core.** { *; }

# Keep Firebase classes
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }