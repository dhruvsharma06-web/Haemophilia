# Room 2.2 creates WorkManager's generated database using reflection.
# Keep the constructor that R8 otherwise removes from the generated class.
-keepclassmembers class androidx.work.impl.WorkDatabase_Impl {
    <init>();
}
