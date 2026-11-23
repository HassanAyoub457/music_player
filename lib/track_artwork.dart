import 'dart:typed_data';

import 'package:flutter/material.dart';

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
