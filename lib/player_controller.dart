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
  String path;
  String title;
  String? artist;
  String? album;
  String? albumArtist;
  String? genre;
  Duration? duration;
  int? bitrate;
  Uint8List? artwork;
  Track(this.path) : title = p.basenameWithoutExtension(path);

  Track clone() => Track(path)
    ..title = title
    ..artist = artist
    ..album = album
    ..albumArtist = albumArtist
    ..genre = genre
    ..duration = duration
    ..bitrate = bitrate
    ..artwork = artwork;
}

class PlayerController extends ChangeNotifier {
  final player = AudioPlayer();
  List<Track> library = [];
  List<Track> queue = [];
  Set<String> favorites = {};
  Set<String> hiddenTracks = {};
  Map<String, List<String>> playlists = {}; // name -> file paths
  Map<String, Track> _index = {};
  ConcatenatingAudioSource? _source;
  bool scanning = false;
  bool _rescanQueued = false;
  bool _askedStorage = false;
  final Map<String, Track> _cache = {}; // path -> track with tags read
  int? sleepMinutes;
  Timer? _sleep;

  /// Shuffle physically reorders [queue] (and the audio source) so the list
  /// shows exactly the order that will play. just_audio's own shuffle mode is
  /// never used, otherwise the list and the real playback order would differ.
  bool shuffled = false;
  List<Track>? _originalOrder; // queue order from before shuffle was turned on
  bool _reordering = false;

  static const _exts = {
    '.mp3',
    '.m4a',
    '.aac',
    '.flac',
    '.wav',
    '.ogg',
    '.opus',
    '.webm',
    '.mkv',
    '.mp4',
    '.m4v',
  };

  static bool _isWhatsAppAudioPath(String path) {
    final parts = p.split(p.normalize(path)).map((part) => part.toLowerCase());
    return parts.any((part) => part.contains('whatsapp'));
  }

  /// Where new downloads go: a normal shared folder (Music/Seal Player) that
  /// any file manager can open. Falls back to the app's private folder if the
  /// app isn't allowed to write there (e.g. all-files access not granted).
  static Future<Directory> downloadDir() async {
    if (Platform.isAndroid) {
      final shared = Directory('/storage/emulated/0/Music/Seal Player');
      try {
        await shared.create(recursive: true);
        final probe = File(p.join(shared.path, '.write_test'));
        await probe.writeAsString('');
        await probe.delete();
        return shared;
      } catch (e) {
        debugPrint('downloadDir: shared folder not writable, using private: $e');
      }
    }
    return _privateMusicDir();
  }

  /// App-private folder used by earlier versions (hidden inside Android/data).
  static Future<Directory> _privateMusicDir() async {
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
    hiddenTracks = (prefs.getStringList('hiddenTracks') ?? []).toSet();
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
      final md = await Future.value(readMetadata(File(path), getImage: true));
      final title = md.title?.trim();
      final artist = md.artist?.trim();
      final album = md.album?.trim();
      final albumArtist = md.albumArtist?.trim();
      if (title != null && title.isNotEmpty) t.title = title;
      if (artist != null && artist.isNotEmpty) t.artist = artist;
      if (album != null && album.isNotEmpty) t.album = album;
      if (albumArtist != null && albumArtist.isNotEmpty) {
        t.albumArtist = albumArtist;
      }
      t.genre = md.genres.isEmpty ? null : md.genres.join(', ');
      t.duration = md.duration;
      t.bitrate = md.bitrate;
      if (md.pictures.isNotEmpty) t.artwork = md.pictures.first.bytes;
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
      await _privateMusicDir(), // older downloads
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
            if (e is File &&
              !_isWhatsAppAudioPath(e.path) &&
              _exts.contains(p.extension(e.path).toLowerCase())) {
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
    final nextQueue = List<Track>.of(tracks);
    final src = ConcatenatingAudioSource(children: [for (final t in nextQueue) _src(t)]);
    try {
      await player.setAudioSource(src, initialIndex: index);
    } on PlayerException catch (e) {
      debugPrint('Unable to load track: ${e.message}');
      return;
    } catch (e) {
      debugPrint('Unable to load queue: $e');
      return;
    }
    queue = nextQueue;
    _source = src;
    _originalOrder = null;
    notifyListeners();
    unawaited(player.play());
    if (shuffled) await _shuffleQueue(); // shuffle stays on for new queues
  }

  Future<void> playShuffled(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    shuffled = true; // playQueue shuffles the new queue, chosen song first
    notifyListeners();
    await playQueue(tracks, Random().nextInt(tracks.length));
  }

  void togglePlay() => player.playing ? player.pause() : player.play();

  Future<void> toggleShuffle() async {
    if (_reordering) return;
    _reordering = true;
    try {
      shuffled = !shuffled;
      notifyListeners();
      if (shuffled) {
        await _shuffleQueue();
      } else {
        await _restoreOrder();
      }
    } finally {
      _reordering = false;
    }
  }

  /// Keeps the playing song (so playback is never interrupted) and puts it
  /// first, followed by every other song in random order.
  Future<void> _shuffleQueue() async {
    final cur = player.currentIndex;
    if (_source == null || cur == null || cur < 0 || cur >= queue.length) {
      return;
    }
    _originalOrder = List<Track>.of(queue);
    final rest = [...queue.sublist(0, cur), ...queue.sublist(cur + 1)]..shuffle();
    await _rebuildAround(const [], rest);
  }

  /// Puts the queue back in the order it had before shuffle was turned on.
  /// Songs removed meanwhile are dropped; songs added meanwhile go at the end.
  Future<void> _restoreOrder() async {
    final orig = _originalOrder;
    _originalOrder = null;
    final cur = player.currentIndex;
    if (orig == null || _source == null || cur == null || cur < 0 || cur >= queue.length) {
      return;
    }
    final now = queue[cur];
    final inQueue = Set<Track>.identity()..addAll(queue);
    final ordered = [for (final t in orig) if (inQueue.contains(t)) t];
    final known = Set<Track>.identity()..addAll(ordered);
    ordered.addAll(queue.where((t) => !known.contains(t)));
    final k = ordered.indexWhere((t) => identical(t, now));
    if (k < 0) return;
    await _rebuildAround(ordered.sublist(0, k), ordered.sublist(k + 1));
  }

  /// Replaces everything except the playing song with [before] and [after].
  Future<void> _rebuildAround(List<Track> before, List<Track> after) async {
    final src = _source;
    final cur = player.currentIndex;
    if (src == null || cur == null || cur < 0 || cur >= queue.length) return;
    final now = queue[cur];
    if (cur + 1 < queue.length) await src.removeRange(cur + 1, queue.length);
    if (cur > 0) await src.removeRange(0, cur);
    if (before.isNotEmpty) await src.insertAll(0, [for (final t in before) _src(t)]);
    if (after.isNotEmpty) await src.addAll([for (final t in after) _src(t)]);
    queue = [...before, now, ...after];
    notifyListeners();
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

  Future<void> hideTracks(Iterable<Track> tracks) async {
    final paths = tracks.map((track) => track.path).toSet();
    if (paths.isEmpty) return;
    hiddenTracks.addAll(paths);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('hiddenTracks', hiddenTracks.toList());
    notifyListeners();
  }

  Future<void> unhideTrack(String path) async {
    if (!hiddenTracks.remove(path)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('hiddenTracks', hiddenTracks.toList());
    await scan();
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

  Future<void> clearQueue() async {
    final src = _source;
    if (src == null || queue.isEmpty) return;
    await player.stop();
    await src.clear();
    queue.clear();
    _source = null;
    _originalOrder = null;
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

  Future<void> editTrackTags(
    Track track, {
    required String title,
    required String artist,
    required String album,
    required String genre,
  }) async {
    final oldPath = track.path;
    final oldFile = File(oldPath);
    final cleanTitle = title.trim();
    final newTitle = cleanTitle.isEmpty
        ? p.basenameWithoutExtension(oldPath)
        : cleanTitle.replaceAll(RegExp(r'[/\\]'), '_');
    final newPath = p.join(p.dirname(oldPath), '$newTitle${p.extension(oldPath)}');
    final pathChanged = p.normalize(newPath) != p.normalize(oldPath);

    if (pathChanged && await File(newPath).exists()) {
      throw FileSystemException('A file with that name already exists.', newPath);
    }

    // Write tags first so a tag-writing failure leaves the original filename intact.
    await Future<void>(() {
      updateMetadata(oldFile, (metadata) {
        metadata
          ..setTitle(cleanTitle)
          ..setArtist(artist.trim())
          ..setAlbum(album.trim())
          ..setGenres(genre.trim().isEmpty ? [] : [genre.trim()]);
      });
    });

    if (pathChanged) {
      await oldFile.rename(newPath);
      for (final playlistTracks in playlists.values) {
        for (var i = 0; i < playlistTracks.length; i++) {
          if (playlistTracks[i] == oldPath) playlistTracks[i] = newPath;
        }
      }
      if (favorites.remove(oldPath)) favorites.add(newPath);
      if (hiddenTracks.remove(oldPath)) hiddenTracks.add(newPath);
      _cache.remove(oldPath);
      track.path = newPath;
    }

    track
      ..title = newTitle
      ..artist = artist.trim().isEmpty ? null : artist.trim()
      ..album = album.trim().isEmpty ? null : album.trim()
      ..genre = genre.trim().isEmpty ? null : genre.trim();
    _cache[track.path] = track;
    _index.remove(oldPath);
    _index[track.path] = track;
    for (final item in [...library, ...queue]) {
      if (item.path == oldPath && !identical(item, track)) {
        item
          ..path = track.path
          ..title = track.title
          ..artist = track.artist
          ..album = track.album
          ..albumArtist = track.albumArtist
          ..genre = track.genre;
      }
    }
    if (pathChanged) {
      await _savePlaylists();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('fav', favorites.toList());
      await prefs.setStringList('hiddenTracks', hiddenTracks.toList());
    }
    notifyListeners();
  }

  Future<void> editTrackCover(Track track, String imagePath) async {
    final imageFile = File(imagePath);
    final ext = p.extension(imagePath).toLowerCase();
    final mime = switch (ext) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      _ => null,
    };
    if (mime == null) throw const FormatException('Choose a JPG or PNG image.');
    final bytes = await imageFile.readAsBytes();
    await Future<void>(() {
      updateMetadata(File(track.path), (metadata) {
        metadata.setPictures([Picture(bytes, mime, PictureType.coverFront)]);
      });
    });
    track.artwork = bytes;
    _cache[track.path] = track;
    for (final item in [...library, ...queue]) {
      if (item.path == track.path) item.artwork = bytes;
    }
    notifyListeners();
  }

  Future<void> refreshTrack(Track track) async {
    final refreshed = await _load(track.path);
    track
      ..title = refreshed.title
      ..artist = refreshed.artist
      ..album = refreshed.album
      ..albumArtist = refreshed.albumArtist
      ..genre = refreshed.genre
      ..duration = refreshed.duration
      ..bitrate = refreshed.bitrate
      ..artwork = refreshed.artwork;
    _cache[track.path] = track;
    notifyListeners();
  }

  Future<void> reorderPlaylist(String name, int oldIndex, int newIndex) async {
    final tracks = playlists[name];
    if (tracks == null || oldIndex < 0 || oldIndex >= tracks.length) return;
    if (newIndex > oldIndex) newIndex--;
    if (newIndex < 0 || newIndex >= tracks.length) return;
    final path = tracks.removeAt(oldIndex);
    tracks.insert(newIndex, path);
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
