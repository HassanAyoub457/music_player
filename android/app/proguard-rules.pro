# Media notification / background playback
-keep class com.ryanheise.** { *; }
-keep class androidx.media.** { *; }
-keep class androidx.media3.** { *; }

# yt-dlp / ffmpeg wrapper (uses reflection and JSON mapping)
-keep class com.yausername.** { *; }
-keep class com.fasterxml.jackson.** { *; }
-dontwarn com.fasterxml.jackson.**

# youtubedl-android unzips its bundled Python with commons-compress, which
# registers classes by reflection at startup; R8 renaming/merging breaks that
# ("class ... is not a concrete class").
-keep class org.apache.commons.compress.** { *; }
-keep class org.apache.commons.io.** { *; }
-dontwarn org.apache.commons.compress.**
-dontwarn org.apache.commons.io.**
-dontwarn org.tukaani.xz.**
-dontwarn com.github.luben.zstd.**
-dontwarn org.brotli.dec.**
