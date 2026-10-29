import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Track {
  final String path;
  String title;
  String? artist;
  String? album;
  Track(this.path) : title = p.basenameWithoutExtension(path);

  Track clone() => Track(path)
    ..title = title
    ..artist = artist
    ..album = album;
}

class PlayerController extends ChangeNotifier {
  final player = AudioPlayer();
  List<Track> library = [];
  List<Track> queue = [];
  Set<String> favorites = {};
  Map<String, List<String>> playlists = {}; // name -> file paths
  Map<String, Track> _index = {};
  ConcatenatingAudioSource? _source;
  bool scanning = false;
  bool _rescanQueued = false;
  bool _askedStorage = false;
  final Map<String, Track> _cache = {}; // path -> track with tags read
  int? sleepMinutes;
  Timer? _sleep;

  static const _exts = {
    '.mp3',
    '.m4a',
    '.aac',
    '.flac',
    '.wav',
    '.ogg',
    '.opus',
    '.mp4',
    '.webm',
    '.mkv',
  };

  static Future<Directory> downloadDir() async {
    final base =
        await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'Music'));
    await d.create(recursive: true);
    return d;
  }

  Track? get current {
    final i = player.currentIndex;
    return (i != null && i < queue.length) ? queue[i] : null;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    favorites = (prefs.getStringList('fav') ?? []).toSet();
    final raw = prefs.getString('playlists');
    if (raw != null) {
      try {
        playlists = (jsonDecode(raw) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, List<String>.from(v as List)));
      } catch (_) {}
    }
    player.currentIndexStream.listen((_) => notifyListeners());
    player.shuffleModeEnabledStream.listen((_) => notifyListeners());
    player.loopModeStream.listen((_) => notifyListeners());
    player.speedStream.listen((_) => notifyListeners());
    await scan();
  }

  /// Requests whichever storage permission applies to this Android version.
  /// Requests that don't apply just return a harmless status.
  Future<void> _requestStorage() async {
    if (!Platform.isAndroid || _askedStorage) return;
    _askedStorage = true;
    await Permission.notification.request();
    await Permission.storage.request(); // Android 12 and below
    await Permission.audio.request(); // Android 13+
    if (!await Permission.manageExternalStorage.isGranted) {
      await Permission.manageExternalStorage.request(); // Android 11+ only
    }
    debugPrint(
      'storage=${await Permission.storage.status} '
      'audio=${await Permission.audio.status} '
      'manage=${await Permission.manageExternalStorage.status}',
    );
  }

  /// Uses the embedded title/artist/album tags when present,
  /// otherwise keeps the filename as the title.
  Future<Track> _load(String path) async {
    final t = Track(path);
    try {
      final md = await Future.value(readMetadata(File(path), getImage: false));
      final title = md.title?.trim();
      final artist = md.artist?.trim();
      final album = md.album?.trim();
      if (title != null && title.isNotEmpty) t.title = title;
      if (artist != null && artist.isNotEmpty) t.artist = artist;
      if (album != null && album.isNotEmpty) t.album = album;
    } catch (_) {
      // unsupported format or no tags: filename fallback
    }
    return t;
  }

  Future<void> scan() async {
    if (scanning) {
      _rescanQueued = true; // run again once the current scan finishes
      return;
    }
    scanning = true;
    notifyListeners();

    await _requestStorage();

    final roots = [
      await downloadDir(),
      Directory('/storage/emulated/0/Music'),
      Directory('/storage/emulated/0/Download'),
      Directory('/storage/emulated/0/Download/Seal/Audio'),
      Directory('/storage/emulated/0/Download/Seal/fav songs'),
    ];
    final found = <String>{};
    for (final dir in roots) {
      try {
        if (!await dir.exists()) {
          debugPrint('scan: missing or not accessible: ${dir.path}');
          continue;
        }
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File && _exts.contains(p.extension(e.path).toLowerCase())) {
            found.add(e.path);
          }
        }
      } catch (e) {
        debugPrint('scan: error in ${dir.path}: $e');
      }
    }
    final tracks = <Track>[];
    var n = 0;
    for (final path in found) {
      tracks.add(_cache[path] ??= await _load(path));
      if (++n % 20 == 0) await Future.delayed(Duration.zero); // keep UI smooth
    }
    library = tracks
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    _index = {for (final t in library) t.path: t};
    scanning = false;
    notifyListeners();

    if (_rescanQueued) {
      _rescanQueued = false;
      await scan();
    }
  }

  AudioSource _src(Track t) => AudioSource.uri(
        Uri.file(t.path),
        tag: MediaItem(
          id: t.path,
          title: t.title,
          artist: t.artist,
          album: t.album,
        ),
      );

  Future<void> playQueue(List<Track> tracks, int index) async {
    if (tracks.isEmpty) return;
    queue = List.of(tracks);
    final src = ConcatenatingAudioSource(children: [for (final t in queue) _src(t)]);
    _source = src;
    await player.setAudioSource(src, initialIndex: index);
    notifyListeners();
    unawaited(player.play());
  }

  Future<void> playShuffled(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    await player.setShuffleModeEnabled(true);
    await playQueue(tracks, Random().nextInt(tracks.length));
    await player.shuffle();
  }

  void togglePlay() => player.playing ? player.pause() : player.play();

  Future<void> toggleShuffle() async {
    final on = !player.shuffleModeEnabled;
    await player.setShuffleModeEnabled(on);
    if (on) await player.shuffle();
  }

  void cycleLoop() {
    const order = [LoopMode.off, LoopMode.all, LoopMode.one];
    player.setLoopMode(order[(order.indexOf(player.loopMode) + 1) % 3]);
  }

  void setSleep(int? minutes) {
    _sleep?.cancel();
    sleepMinutes = minutes;
    if (minutes != null) {
      _sleep = Timer(Duration(minutes: minutes), () {
        player.pause();
        sleepMinutes = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  Future<void> toggleFavorite(Track t) async {
    favorites.contains(t.path)
        ? favorites.remove(t.path)
        : favorites.add(t.path);
    (await SharedPreferences.getInstance()).setStringList(
      'fav',
      favorites.toList(),
    );
    notifyListeners();
  }

  Future<void> delete(Track t) async {
    try {
      await File(t.path).delete();
    } catch (_) {}
    for (final l in playlists.values) {
      l.remove(t.path);
    }
    await _savePlaylists();
    await scan();
  }

  // ---------------- queue ----------------

  /// Inserts right after the current song. With shuffle on, "next" follows
  /// the shuffled order, so the song may not play immediately after.
  Future<void> playNext(Track t) async {
    final src = _source;
    if (src == null || queue.isEmpty) return playQueue([t], 0);
    final at = (player.currentIndex ?? -1) + 1;
    queue.insert(at, t.clone());
    await src.insert(at, _src(t));
    await _resumeIfFinished();
    notifyListeners();
  }

  Future<void> addToQueue(Track t) async {
    final src = _source;
    if (src == null || queue.isEmpty) return playQueue([t], 0);
    queue.add(t.clone());
    await src.add(_src(t));
    await _resumeIfFinished();
    notifyListeners();
  }

  Future<void> _resumeIfFinished() async {
    if (player.processingState == ProcessingState.completed) {
      await player.seekToNext();
      unawaited(player.play());
    }
  }

  Future<void> moveInQueue(int from, int to) async {
    final src = _source;
    if (src == null) return;
    queue.insert(to, queue.removeAt(from));
    await src.move(from, to);
    notifyListeners();
  }

  Future<void> removeFromQueue(int i) async {
    final src = _source;
    if (src == null || i < 0 || i >= queue.length) return;
    queue.removeAt(i);
    await src.removeAt(i);
    notifyListeners();
  }

  Future<void> jumpTo(int i) async {
    await player.seek(Duration.zero, index: i);
    unawaited(player.play());
  }

  // ---------------- playlists ----------------

  Future<void> _savePlaylists() async => (await SharedPreferences.getInstance())
      .setString('playlists', jsonEncode(playlists));

  List<Track> tracksOf(String name) => [
        for (final path in playlists[name] ?? const <String>[])
          if (_index[path] != null) _index[path]!,
      ];

  Future<bool> createPlaylist(String name, {Track? add}) async {
    name = name.trim();
    if (name.isEmpty || playlists.containsKey(name)) return false;
    playlists[name] = [if (add != null) add.path];
    await _savePlaylists();
    notifyListeners();
    return true;
  }

  Future<bool> renamePlaylist(String old, String name) async {
    name = name.trim();
    if (name.isEmpty || playlists.containsKey(name)) return false;
    playlists = {
      for (final e in playlists.entries) (e.key == old ? name : e.key): e.value,
    };
    await _savePlaylists();
    notifyListeners();
    return true;
  }

  Future<void> deletePlaylist(String name) async {
    playlists.remove(name);
    await _savePlaylists();
    notifyListeners();
  }

  /// Returns false if the song was already in the playlist.
  Future<bool> addToPlaylist(String name, Track t) async {
    final l = playlists[name];
    if (l == null || l.contains(t.path)) return false;
    l.add(t.path);
    await _savePlaylists();
    notifyListeners();
    return true;
  }

  Future<void> addManyToPlaylist(String name, Iterable<String> paths) async {
    final l = playlists[name];
    if (l == null) return;
    for (final p in paths) {
      if (!l.contains(p)) l.add(p);
    }
    await _savePlaylists();
    notifyListeners();
  }

  Future<void> removeFromPlaylist(String name, Track t) async {
    playlists[name]?.remove(t.path);
    await _savePlaylists();
    notifyListeners();
  }

  @override
  void dispose() {
    _sleep?.cancel();
    player.dispose();
    super.dispose();
  }
}