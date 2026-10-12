# Flutter / Dart wrapper rules — R8 full mode strips the entry points these
# plugins reach only via JNI/reflection.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Google Play Services / Maps are referenced reflectively by the maps SDK.
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Kotlin metadata is read by the plugin registrant at runtime.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Line numbers make release crash reports readable; hide the original file.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile