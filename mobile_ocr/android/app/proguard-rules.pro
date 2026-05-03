# Keep rules for Google ML Kit Text Recognition
# Suppress missing optional language model classes (Chinese, Japanese, Korean, Devanagari)
# We only use Latin script, so these are safe to ignore.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Suppress missing Google Play Core split install classes (used by Flutter deferred components, not needed here)
-dontwarn com.google.android.play.core.**

# Keep ML Kit classes
-keep class com.google.mlkit.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }

# Flutter standard rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
