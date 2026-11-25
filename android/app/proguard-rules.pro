# Media notification / background playback
-keep class com.ryanheise.** { *; }
-keep class androidx.media.** { *; }
-keep class androidx.media3.** { *; }

# yt-dlp / ffmpeg wrapper (uses reflection and JSON mapping)
-keep class com.yausername.** { *; }
-keep class com.fasterxml.jackson.** { *; }
-dontwarn com.fasterxml.jackson.**
