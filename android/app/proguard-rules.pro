# commons-compress discovers ZIP extra-field classes through reflection when
# youtubedl-android extracts its bundled Python runtime. Keep just this package
# so optional compressors (such as XZ) remain removable by R8.
-keep class org.apache.commons.compress.archivers.zip.** { *; }
