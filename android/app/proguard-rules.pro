# Preserve Dio and network-related classes
-keep class io.flutter.** { *; }
-keep class com.example.elegant_store.** { *; }

# Preserve Dio HTTP client
-keep class io.flutter.plugins.** { *; }
-keep class okhttp3.** { *; }
-keep class retrofit2.** { *; }
-keep class com.google.gson.** { *; }

# Preserve all Flutter-related classes
-keep class * extends io.flutter.embedding.engine.FlutterEngine { *; }
-keep class * extends io.flutter.embedding.engine.dart.DartExecutor { *; }

# Don't warn about missing classes
-dontwarn okhttp3.**
-dontwarn retrofit2.**
-dontwarn com.google.gson.**
-dontwarn io.flutter.**

# Preserve line numbers for debugging
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
