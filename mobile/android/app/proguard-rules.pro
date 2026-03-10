# Flutter-specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Hive — keep model class names (used as map keys in JSON serialisation)
-keep class com.hive.** { *; }
-keepnames class * extends com.hive.flutter.**

# audioplayers
-keep class xyz.luan.audioplayers.** { *; }

# flutter_blue_plus
-keep class com.boskokg.flutter_blue_plus.** { *; }

# geolocator
-keep class com.baseflow.geolocator.** { *; }

# flutter_foreground_task
-keep class com.pravera.flutter_foreground_task.** { *; }

# flutter_tts
-keep class com.tundralabs.fluttertts.** { *; }

# Kotlin serialisation / reflection (used by several plugins)
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepclassmembers class ** {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Suppress warnings for missing optional classes
-dontwarn io.flutter.embedding.**
-dontwarn com.google.android.play.core.**
