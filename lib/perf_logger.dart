import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// Writes one CSV row per rendered frame (build / raster / total time in ms
/// and whether music is playing), plus "# ..." marker lines when playback
/// changes. Profile/debug builds only; does nothing in release.
///
/// Target: /storage/emulated/0/Download/seal_perf_log.csv
/// If that folder is not writable yet (storage permission not granted), the
/// log goes to the app's external folder and is moved to Download the moment
/// it becomes writable. The path in use is always printed in the console.
class PerfLog {
  static final _all = StringBuffer(); // everything recorded so far
  static final _pending = StringBuffer(); // not yet written
  static final _clock = Stopwatch();
  static bool _started = false;
  static bool _playing = false;
  static bool _busy = false;
  static bool _downloadWorks = false;
  static File? _fallback;
  static Timer? _flush;

  static const _header = 't_ms,build_ms,raster_ms,total_ms,vsync_ms,playing';

  static Future<void> start() async {
    if (kReleaseMode || _started) return;
    _started = true;
    _clock.start();
    _emit(_header);
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _flush = Timer.periodic(const Duration(seconds: 3), (_) => _write());
    debugPrint('PerfLog: started (target /storage/emulated/0/Download/seal_perf_log.csv)');
  }

  /// Adds a marker line whenever playback starts, pauses or changes state.
  static void attach(AudioPlayer player) {
    if (kReleaseMode) return;
    _playing = player.playing;
    player.playerStateStream.listen((s) {
      _playing = s.playing;
      mark('playing=${s.playing} state=${s.processingState.name}');
    });
  }

  static void mark(String label) {
    if (kReleaseMode) return;
    _emit('# ${_clock.elapsedMilliseconds} $label');
  }

  static void _emit(String line) {
    _all.writeln(line);
    _pending.writeln(line);
  }

  static double _ms(Duration d) => d.inMicroseconds / 1000;

  static void _onTimings(List<FrameTiming> timings) {
    final now = _clock.elapsedMilliseconds;
    for (final t in timings) {
      _emit(
        '$now,${_ms(t.buildDuration).toStringAsFixed(2)},'
        '${_ms(t.rasterDuration).toStringAsFixed(2)},'
        '${_ms(t.totalSpan).toStringAsFixed(2)},'
        '${_ms(t.vsyncOverhead).toStringAsFixed(2)},${_playing ? 1 : 0}',
      );
    }
  }

  static Future<void> _write() async {
    if (_busy || _pending.isEmpty) return;
    _busy = true;
    try {
      final text = _pending.toString();
      _pending.clear();
      final download = File('/storage/emulated/0/Download/seal_perf_log.csv');

      if (!_downloadWorks) {
        // (Re)try Download: write everything recorded so far in one go.
        try {
          await download.writeAsString(_all.toString(), flush: true);
          _downloadWorks = true;
          debugPrint('PerfLog: writing to ${download.path}');
          return;
        } catch (_) {
          // not allowed yet; keep a copy where the app can always write
          final f = _fallback ??= await _openFallback();
          await f.writeAsString(text, mode: FileMode.append);
          return;
        }
      }
      await download.writeAsString(text, mode: FileMode.append);
    } catch (e) {
      debugPrint('PerfLog: write failed: $e');
    } finally {
      _busy = false;
    }
  }

  static Future<File> _openFallback() async {
    final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/seal_perf_log.csv');
    await f.writeAsString('', flush: true);
    debugPrint('PerfLog: Download not writable yet, using ${f.path}');
    return f;
  }
}
