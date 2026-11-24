import 'dart:async';
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: image != null && image.isNotEmpty
            // ignore: unnecessary_underscores
            ? Image.memory(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(colors))
            : _placeholder(colors),
      ),
    );
  }

  Widget _placeholder(ColorScheme colors) => ColoredBox(
        color: playing ? colors.primaryContainer : colors.surfaceContainerHighest,
        child: Icon(
          playing ? Icons.equalizer : Icons.music_note,
          color: playing ? colors.primary : colors.onSurfaceVariant,
        ),
      );
}

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

class _SpinningDiscState extends State<SpinningDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30), // one full turn
  );
  StreamSubscription<PlayerState>? _sub;

  @override
  void initState() {
    super.initState();
    final player = context.read<PlayerController>().player;
    _apply(player.playerState);
    _sub = player.playerStateStream.listen(_apply);
  }

  void _apply(PlayerState s) {
    if (!mounted) return;
    final spinning = s.playing &&
        s.processingState != ProcessingState.completed &&
        s.processingState != ProcessingState.idle;
    if (spinning) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop(); // keeps the current angle
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final s = widget.size;
    final art = s * 0.75;
    final image = widget.bytes;
    return RepaintBoundary(
      child: RotationTransition(
        turns: _spin,
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
                      ? Image.memory(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback(colors))
                      : _fallback(colors),
                ),
              ),
              // spindle hole
              // Container(
              //   width: s * 0.1,
              //   height: s * 0.1,
              //   decoration: BoxDecoration(
              //     shape: BoxShape.circle,
              //     color: Colors.black,
              //     border: Border.all(color: Colors.white24, width: 0.6),
              //   ),
              // ),
            ],
          ),
        ),
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
    final rect = Rect.fromCircle(center: center, radius: outer);

    // disc body
    canvas.drawCircle(center, outer, Paint()..color = const Color(0xFF111111));

    // grooves
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = Colors.white.withValues(alpha: 0.10);
    final step = size.width * 0.035;
    for (var r = innerRadius + step; r < outer - 1; r += step) {
      canvas.drawCircle(center, r, groove);
    }

    // soft light sheen
    canvas.drawCircle(
      center,
      outer,
      Paint()
        ..shader = SweepGradient(colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.14),
          Colors.transparent,
          Colors.transparent,
          Colors.white.withValues(alpha: 0.14),
          Colors.transparent,
        ], stops: const [0, 0.12, 0.25, 0.5, 0.62, 0.75]).createShader(rect),
    );

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
