import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'player_controller.dart';

class DownloadJob {
  final String id;
  final String url;
  String title;
  double progress = 0;
  String status = 'Starting…';
  bool done = false, failed = false, cancelled = false;
  DownloadJob(this.id, this.url) : title = url;
}

/// Talks to MainActivity.kt, which runs yt-dlp + FFmpeg via the
/// youtubedl-android library (the same engine Seal uses).
class Downloader extends ChangeNotifier {
  static const _m = MethodChannel('seal_player/ytdlp');
  static const _e = EventChannel('seal_player/ytdlp_events');

  final Map<String, DownloadJob> jobs = {};
  VoidCallback? onFinished;
  bool ready = false;
  String? initError;

  Downloader() {
    _e.receiveBroadcastStream().listen(_onEvent);
    _init();
  }

  Future<void> _init() async {
    try {
      await _m.invokeMethod('init');
      ready = true;
    } on PlatformException catch (e) {
      initError = e.message;
    } on MissingPluginException {
      initError = 'Downloads are only supported on Android.';
    }
    notifyListeners();
  }

  Future<void> start(
    String url, {
    required bool audio,
    required String format,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    jobs[id] = DownloadJob(id, url);
    notifyListeners();
    final dir = await PlayerController.downloadDir();
    try {
      await _m.invokeMethod('download', {
        'id': id,
        'url': url,
        'audioOnly': audio,
        'format': format,
        'outDir': dir.path,
      });
    } on PlatformException catch (e) {
      jobs[id]!
        ..failed = true
        ..status = e.message ?? 'Failed';
      notifyListeners();
    }
  }

  bool updating = false;
  String? updateMessage;

  Future<void> updateEngine() async {
    updating = true;
    updateMessage = null;
    notifyListeners();
    try {
      final r = await _m.invokeMethod<String>('update');
      updateMessage = 'yt-dlp update: $r'; // DONE or ALREADY_UP_TO_DATE
    } on PlatformException catch (e) {
      updateMessage = 'Update failed: ${e.message}';
    }
    updating = false;
    notifyListeners();
  }

  Future<void> cancel(String id) async {
    final j = jobs[id];
    if (j == null || j.done) return;
    j.cancelled = true;
    j.status = 'Cancelled';
    notifyListeners();
    await _m.invokeMethod('cancel', {'id': id});
  }

  void clearFinished() {
    jobs.removeWhere((_, j) => j.done || j.failed || j.cancelled);
    notifyListeners();
  }

  void _onEvent(dynamic ev) {
    final m = Map<String, dynamic>.from(ev as Map);
    final j = jobs[m['id']];
    if (j == null) return;
    switch (m['type']) {
      case 'title':
        j.title = m['title'] as String;
      case 'progress':
        j.progress = ((m['progress'] as num).toDouble() / 100).clamp(0.0, 1.0);
        final eta = (m['eta'] as num).toInt();
        j.status =
            'Downloading ${(j.progress * 100).toStringAsFixed(0)}%'
            '${eta > 0 ? ' · ${eta}s left' : ''}';
      case 'done':
        j.done = true;
        j.progress = 1;
        j.status = 'Done';
        onFinished?.call();
      case 'error':
        if (!j.cancelled) {
          j.failed = true;
          j.status = m['message'] as String? ?? 'Failed';
        }
    }
    notifyListeners();
  }
}
