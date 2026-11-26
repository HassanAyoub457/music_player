import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'player_controller.dart';

/// One row of a YouTube search.
class SearchResult {
  final String id, title, channel, url;
  final double? duration; // seconds; null for live streams
  const SearchResult({
    required this.id,
    required this.title,
    required this.channel,
    required this.url,
    this.duration,
  });

  String get thumbnail => 'https://i.ytimg.com/vi/$id/mqdefault.jpg';

  factory SearchResult.fromMap(Map<String, dynamic> m) => SearchResult(
        id: m['id'] as String,
        title: m['title'] as String? ?? '',
        channel: m['channel'] as String? ?? '',
        url: m['url'] as String? ?? 'https://www.youtube.com/watch?v=${m['id']}',
        duration: (m['duration'] as num?)?.toDouble(),
      );
}

class DownloadJob {
  final String id;
  final String url;
  String title;
  double progress = 0;
  String status = 'Starting…';
  bool done = false, failed = false, cancelled = false;
  String outDir = '';
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

  /// Searches YouTube through yt-dlp, so no API key is needed.
  Future<List<SearchResult>> search(String query, {int count = 15}) async {
    final raw = await _m.invokeMethod<List<dynamic>>('search', {'query': query, 'count': count});
    return [
      for (final r in raw ?? const []) SearchResult.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// Starts a download and returns its job id.
  Future<String> start(String url, {required bool audio, required String format, String? title}) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    jobs[id] = DownloadJob(id, url);
    if (title != null && title.isNotEmpty) jobs[id]!.title = title;
    notifyListeners();
    final dir = await PlayerController.downloadDir();
    jobs[id]!.outDir = dir.path;
    try {
      await _m.invokeMethod('download', {'id': id, 'url': url, 'audioOnly': audio, 'format': format, 'outDir': dir.path});
    } on PlatformException catch (e) {
      jobs[id]!
        ..failed = true
        ..status = e.message ?? 'Failed';
      notifyListeners();
    }
    return id;
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
        j.status = j.outDir.isEmpty ? 'Done' : 'Done · saved to ${j.outDir}';
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
