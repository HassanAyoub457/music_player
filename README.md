# Seal Player (Flutter, Android)

Music player + yt-dlp downloader. The downloader uses the same engine as
[Seal](https://github.com/junkfood02/Seal): the `youtubedl-android` library
(yt-dlp + FFmpeg), called from Flutter through a platform channel.

## Setup

```bash
flutter create --org com.example --project-name seal_player seal_player
cd seal_player
# copy this package's lib/ over, and MainActivity.kt to:
#   android/app/src/main/kotlin/com/example/seal_player/MainActivity.kt
```
Then merge `pubspec_dependencies.yaml` into `pubspec.yaml` and run `flutter pub get`.

### android/app/build.gradle(.kts)
```kotlin
android {
    defaultConfig { minSdk = 24 }
    packaging { jniLibs { useLegacyPackaging = true } }   // required by youtubedl-android
}
dependencies {
    implementation("io.github.junkfood02.youtubedl-android:library:0.17.2")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:0.17.2")
}
```
(Check Seal's `gradle/libs.versions.toml` for the current version.)
Tip: build with `flutter build apk --split-per-abi` – the yt-dlp binaries are large.

### android/app/src/main/AndroidManifest.xml
Add `xmlns:tools="http://schemas.android.com/tools"` to `<manifest>`, then:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>

<application android:extractNativeLibs="true" ... >
  <!-- inside <application>, next to <activity> -->
  <service android:name="com.ryanheise.audioservice.AudioService"
      android:foregroundServiceType="mediaPlayback" android:exported="true"
      tools:ignore="Instantiatable">
    <intent-filter><action android:name="android.media.browse.MediaBrowserService"/></intent-filter>
  </service>
  <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
      android:exported="true" tools:ignore="Instantiatable">
    <intent-filter><action android:name="android.intent.action.MEDIA_BUTTON"/></intent-filter>
  </receiver>
</application>
```

Run: `flutter run`
