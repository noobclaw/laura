# home_widget pulls in WorkManager + Room. R8 strips the generated
# WorkDatabase implementation in release builds, so the app dies inside
# androidx.startup's InitializationProvider before Flutter even boots
# ("Failed to create an instance of androidx.work.impl.WorkDatabase").
# Keep both libraries whole — the app is tiny, size cost is negligible.
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
