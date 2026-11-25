import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import 'player_controller.dart';

class TrackArtwork extends StatelessWidget {
  final Uint8List? bytes;
  final double size;
  final bool playing;

  const TrackArtwork({super.key, required this.bytes, this.size = 52, this.playing = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final image = bytes;
    // A small oversampling cushion keeps thumbnails crisp without decoding
    // the full-size embedded cover.
    final cacheSize = (size * 1.25 * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: image != null && image.isNotEmpty
            // ignore: unnecessary_underscores
            ? Image.memory(
                image,
                fit: BoxFit.cover,
                cacheWidth: cacheSize,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                errorBuilder: (_, __, ___) => _placeholder(colors),
              )
            : _placeholder(colors),
      ),
    );
  }

  Widget _placeholder(ColorScheme colors) => ColoredBox(
    color: playing ? colors.primaryContainer : colors.surfaceContainerHighest,
    child: Icon(playing ? Icons.equalizer : Icons.music_note, color: playing ? colors.primary : colors.onSurfaceVariant),
  );
}

/// Disc updates per second while playing. 0 = disc never rotates.
/// Profiling switch: `--dart-define=DISC_HZ=15` to try a lower rate.
/// 60 is the default: a slower update rate let the phone's GPU clock down
/// between frames, which made each frame take longer in the profile traces.
const int kDiscHz = int.fromEnvironment('DISC_HZ', defaultValue: 60);

/// Vinyl-record look: dark grooved disc on the outside, the cover art on top
/// in the middle. Rotates while the player is playing and keeps its angle
/// when paused.
class SpinningDisc extends StatefulWidget {
  final Uint8List? bytes;
  final double size;

  const SpinningDisc({super.key, required this.bytes, this.size = 52});

  @override
  State<SpinningDisc> createState() => _SpinningDiscState();
}

class _SpinningDiscState extends State<SpinningDisc> {
  // The disc turns slowly (one lap per 30 s), so updating it ~15 times a
  // second looks identical to 60 fps but asks the GPU to redraw the whole
  // screen a quarter as often. A vsync-driven AnimationController would force
  // a full-scene raster on every single frame while music plays.
  static final _tick = Duration(milliseconds: kDiscHz > 0 ? (1000 / kDiscHz).round() : 1000);
  static final _turnsPerTick = _tick.inMilliseconds / 30000; // 30 s per full turn

  final _turns = ValueNotifier<double>(0);
  StreamSubscription<PlayerState>? _sub;
  Timer? _timer;
  bool _playing = false;
  bool _visible = true; // false while another page covers this one

  @override
  void initState() {
    super.initState();
    final player = context.read<PlayerController>().player;
    _apply(player.playerState);
    _sub = player.playerStateStream.listen(_apply);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.of(context); // same signal Flutter uses to pause animations
    _sync();
  }

  void _apply(PlayerState s) {
    if (!mounted) return;
    _playing = s.playing && s.processingState != ProcessingState.completed && s.processingState != ProcessingState.idle;
    _sync();
  }

  void _sync() {
    if (_playing && _visible && kDiscHz > 0) {
      _timer ??= Timer.periodic(_tick, (_) => _turns.value = (_turns.value + _turnsPerTick) % 1.0);
    } else {
      _timer?.cancel(); // keeps the current angle
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final s = widget.size;
    final art = s * 0.75;
    final cacheSize = (art * 1.25 * MediaQuery.devicePixelRatioOf(context)).round();
    final image = widget.bytes;
    // Outer boundary absorbs the per-tick repaint so the mini player around it
    // is not redrawn; the inner boundary caches the disc, so each tick the GPU
    // only rotates one ready-made layer.
    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: _turns,
        child: RepaintBoundary(
          child: SizedBox(
            width: s,
            height: s,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(size: Size.square(s), painter: _VinylPainter(art / 2)),
                ClipOval(
                  child: SizedBox(
                    width: art,
                    height: art,
                    child: image != null && image.isNotEmpty
                        // ignore: unnecessary_underscores
                        ? Image.memory(
                            image,
                            fit: BoxFit.cover,
                            cacheWidth: cacheSize,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.low,
                            errorBuilder: (_, __, ___) => _fallback(colors),
                          )
                        : _fallback(colors),
                  ),
                ),
              ],
            ),
          ),
        ),
        builder: (_, turns, child) => Transform.rotate(angle: turns * 2 * math.pi, child: child),
      ),
    );
  }

  Widget _fallback(ColorScheme colors) => ColoredBox(
    color: colors.primaryContainer,
    child: Icon(Icons.music_note, size: widget.size * 0.3, color: colors.onPrimaryContainer),
  );
}

class _VinylPainter extends CustomPainter {
  final double innerRadius; // where the artwork starts
  const _VinylPainter(this.innerRadius);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.width / 2;

    // disc body
    canvas.drawCircle(center, outer, Paint()..color = const Color(0xFF111111));

    // grooves
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = Colors.white.withValues(alpha: 0.10);
    final step = size.width * 0.065;
    for (var r = innerRadius + step; r < outer - 1; r += step) {
      canvas.drawCircle(center, r, groove);
    }

    // rim
    canvas.drawCircle(
      center,
      outer - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white24,
    );
  }

  @override
  bool shouldRepaint(_VinylPainter old) => old.innerRadius != innerRadius;
}
