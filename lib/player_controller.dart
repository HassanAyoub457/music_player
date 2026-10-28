import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Track {
  final String path;
  final String title;
  Track(this.path) : title = p.basenameWithoutExtension(path);
}

class PlayerController extends ChangeNotifier {
  final player = AudioPlayer();
  List<Track> library = [];
  List<Track> queue = [];
  Set<String> favorites = {};
  bool scanning = false;
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
    player.currentIndexStream.listen((_) => notifyListeners());
    player.shuffleModeEnabledStream.listen((_) => notifyListeners());
    player.loopModeStream.listen((_) => notifyListeners());
    player.speedStream.listen((_) => notifyListeners());
    await scan();
  }

  Future<void> scan() async {
    scanning = true;
    notifyListeners();
    await Permission.audio.request();
    await Permission.notification.request();
    if (!await Permission.manageExternalStorage.isGranted) {
      await Permission.manageExternalStorage.request();
    }
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
        if (!await dir.exists()) continue;
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File && _exts.contains(p.extension(e.path).toLowerCase())) {
            found.add(e.path);
          }
        }
      } catch (_) {}
    }
    library = found.map(Track.new).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    scanning = false;
    notifyListeners();
  }

  Future<void> playQueue(List<Track> tracks, int index) async {
    if (tracks.isEmpty) return;
    queue = List.of(tracks);
    await player.setAudioSource(
      ConcatenatingAudioSource(
        children: [
          for (final t in queue)
            AudioSource.uri(
              Uri.file(t.path),
              tag: MediaItem(id: t.path, title: t.title),
            ),
        ],
      ),
      initialIndex: index,
    );
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
    await scan();
  }

  @override
  void dispose() {
    _sleep?.cancel();
    player.dispose();
    super.dispose();
  }
}
