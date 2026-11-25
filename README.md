# Music Player

A dark red-and-purple music player for Android that also downloads songs from
links. Play the music already on your phone, build playlists, and grab new
tracks or videos with built-in yt-dlp, complete with cover art and tags.

## Features

**Playing music**
- Scans your phone's `Music` and `Download` folders and lists every song it finds
- Background playback with play/pause, previous and next in the notification
- Mini player with a vinyl-style disc that spins while a song plays
- Now Playing screen with shuffle and repeat
- Sleep timer that pauses playback after a set number of minutes

**Queue**
- See what's playing and what's coming up, and jump to any song
- Drag to reorder, swipe to remove, or add songs with "Play next" and "Add to queue"
- Shuffle actually reorders the queue, so the list shows the exact order that will play. Turn it off to get your original order back

**Your library**
- Search, favorites, and playlists you can create, rename and reorder
- Hide songs you don't want to see, or delete them
- Edit a song's title, artist, album, genre and cover image

**Downloads**
- Paste a link and choose audio (mp3, m4a, opus and more) or video (mp4)
- Cover art is embedded in the file, cropped square, along with title and artist
- Files are saved to `Music/Seal Player`, a normal folder you can open in any file manager. If the app isn't allowed to write there, it falls back to its private folder
- Finished downloads show up in your library automatically

> Only download content you own or have permission to save.

## Getting started

You need [Flutter](https://docs.flutter.dev/get-started/install) and an Android
phone or emulator (Android 7.0 / API 24 or newer).

```bash
flutter pub get
flutter run
```

On first launch the app asks for permission to read your music, send
notifications, and access files. Granting all-files access lets it scan every
folder and save downloads to `Music/Seal Player`.

### Building a release APK

```bash
flutter build apk --split-per-abi
```

`--split-per-abi` keeps the APK smaller, since the yt-dlp and FFmpeg binaries
are large. Release builds use `android/app/src/main/res/raw/keep.xml` and
`android/app/proguard-rules.pro` so the notification buttons and the downloader
survive code and resource shrinking. If you ever see missing notification
buttons in a release build, check those two files first.

### Changing the app icon

Put a square PNG at `assets/icon/icon.png`, then run:

```bash
dart run flutter_launcher_icons
```

## Project layout

| File | What it does |
| --- | --- |
| `lib/main.dart` | App entry point, theme and background gradient, bottom navigation |
| `lib/theme.dart` | Colors and gradients |
| `lib/player_controller.dart` | Playback, library scanning, queue, shuffle, playlists, tag editing |
| `lib/downloader.dart` | Download jobs and progress, talks to the native side |
| `lib/library_page.dart`, `playlists_page.dart`, `download_page.dart`, `queue_page.dart` | Main screens |
| `lib/widgets.dart` | Mini player and Now Playing screen |
| `lib/track_artwork.dart` | Cover thumbnails and the spinning disc |
| `android/.../MainActivity.kt` | Runs yt-dlp through a platform channel |

## Built with

- [just_audio](https://pub.dev/packages/just_audio) and
  [just_audio_background](https://pub.dev/packages/just_audio_background) for playback and the notification
- [provider](https://pub.dev/packages/provider) for state
- [audio_metadata_reader](https://pub.dev/packages/audio_metadata_reader) for tags and cover art
- [youtubedl-android](https://github.com/yausername/youtubedl-android) (yt-dlp and FFmpeg), the same engine used by
  [Seal](https://github.com/junkfood02/Seal)
