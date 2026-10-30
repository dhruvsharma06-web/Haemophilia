# Room 2.2 creates WorkManager's generated database using reflection.
# Keep the constructor that R8 otherwise removes from the generated class.
-keepclassmembers class androidx.work.impl.WorkDatabase_Impl {
    <init>();
}

# MediaPipe Tasks ships AutoValue's annotation processor, which references
# compile-time-only javax.lang.model classes. They are never loaded at runtime.
-dontwarn javax.lang.model.**
-dontwarn autovalue.shaded.**
-dontwarn com.google.auto.value.**

# MediaPipe and its protobuf messages are reached through JNI and reflection;
# keep them so release builds track poses exactly like debug builds.
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.mediapipe.**

# ML Kit pose detection (used for every non-world-pose exercise).
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
