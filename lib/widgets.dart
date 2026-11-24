import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import 'player_controller.dart';
import 'queue_page.dart';
import 'track_menu.dart';
import 'track_artwork.dart';

String fmt(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  return '${h > 0 ? '$h:' : ''}${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

class PlayPauseButton extends StatelessWidget {
  final double size;
  const PlayPauseButton({super.key, this.size = 32});
  @override
  Widget build(BuildContext context) {
    final c = context.read<PlayerController>();
    return StreamBuilder<PlayerState>(
      stream: c.player.playerStateStream,
      builder: (_, snap) {
        final s = snap.data;
        final busy =
            s?.processingState == ProcessingState.loading ||
            s?.processingState == ProcessingState.buffering;
        if (busy) {
          return SizedBox(
            width: size,
            height: size,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: CircularProgressIndicator(),
            ),
          );
        }
        return IconButton(
          iconSize: size,
          icon: Icon((s?.playing ?? false) ? Icons.pause : Icons.play_arrow),
          onPressed: c.togglePlay,
        );
      },
    );
  }
}

class MiniPlayer extends StatelessWidget {
  final Widget? trailing;
  const MiniPlayer({super.key, this.trailing});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlayerController>();
    final t = c.current;
    if (t == null) return const SizedBox.shrink();
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NowPlayingPage()),
        ),
        leading: TrackArtwork(bytes: t.artwork, size: 48),
        title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),

        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PlayPauseButton(),
            if (trailing != null)
              trailing!
            else
              IconButton(
                icon: const Icon(Icons.queue_music),
                tooltip: 'Open queue',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QueuePage()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlayerController>();
    final p = c.player;
    final t = c.current;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        // title: const Text('Now playing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music),
            tooltip: 'Queue',
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const QueuePage())),
          ),
          PopupMenuButton<double>(
            icon: const Icon(Icons.speed),
            tooltip: 'Speed',
            onSelected: p.setSpeed,
            itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                .map(
                  (s) => CheckedPopupMenuItem(
                    value: s,
                    checked: p.speed == s,
                    child: Text('${s}x'),
                  ),
                )
                .toList(),
          ),
          PopupMenuButton<int?>(
            icon: Icon(
              c.sleepMinutes == null ? Icons.bedtime_outlined : Icons.bedtime,
            ),
            tooltip: 'Sleep timer',
            onSelected: c.setSleep,
            itemBuilder: (_) => const [
              PopupMenuItem(value: null, child: Text('Off')),
              PopupMenuItem(value: 15, child: Text('15 min')),
              PopupMenuItem(value: 30, child: Text('30 min')),
              PopupMenuItem(value: 60, child: Text('60 min')),
            ],
          ),
          if (t != null)
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => showTrackOptions(context, t),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Spacer(),
            Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              clipBehavior: Clip.antiAlias,
              child: t?.artwork != null && t!.artwork!.isNotEmpty
                  ? Image.memory(
                      t.artwork!,
                      fit: BoxFit.cover,
                      // ignore: unnecessary_underscores
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.music_note,
                        size: 96,
                        color: cs.onPrimaryContainer,
                      ),
                    )
                  : Icon(
                      Icons.music_note,
                      size: 96,
                      color: cs.onPrimaryContainer,
                    ),
            ),
            const SizedBox(height: 32),
            Text(
              t?.title ?? 'Nothing playing',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (t?.artist != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(t!.artist!,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            const SizedBox(height: 16),
            StreamBuilder<Duration>(
              stream: p.positionStream,
              builder: (_, snap) {
                final pos = snap.data ?? Duration.zero;
                final dur = p.duration ?? Duration.zero;
                final max = dur.inMilliseconds <= 0
                    ? 1.0
                    : dur.inMilliseconds.toDouble();
                return Column(
                  children: [
                    Slider(
                      value: pos.inMilliseconds.toDouble().clamp(0, max),
                      max: max,
                      onChanged: (v) =>
                          p.seek(Duration(milliseconds: v.toInt())),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [Text(fmt(pos)), Text(fmt(dur))],
                      ),
                    ),
                  ],
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.shuffle,
                    color: p.shuffleModeEnabled ? cs.primary : null,
                  ),
                  onPressed: c.toggleShuffle,
                ),
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.skip_previous),
                  onPressed: p.seekToPrevious,
                ),
                const PlayPauseButton(size: 64),
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.skip_next),
                  onPressed: p.seekToNext,
                ),
                IconButton(
                  icon: Icon(
                    p.loopMode == LoopMode.one
                        ? Icons.repeat_one
                        : Icons.repeat,
                    color: p.loopMode == LoopMode.off ? null : cs.primary,
                  ),
                  onPressed: c.cycleLoop,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.volume_down),
                Expanded(
                  child: StreamBuilder<double>(
                    stream: p.volumeStream,
                    builder: (_, s) =>
                        Slider(value: s.data ?? 1, onChanged: p.setVolume),
                  ),
                ),
                const Icon(Icons.volume_up),
                if (t != null)
                  IconButton(
                    icon: Icon(
                      c.favorites.contains(t.path)
                          ? Icons.favorite
                          : Icons.favorite_border,
                    ),
                    onPressed: () => c.toggleFavorite(t),
                  ),
              ],
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
