import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'player_controller.dart';
import 'track_artwork.dart';
import 'track_menu.dart';
import 'widgets.dart' show MiniPlayer;

class QueuePage extends StatefulWidget {
  const QueuePage({super.key});

  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  // Every queue row is forced to this height (see itemExtent below), so the
  // scroll offset for a given index is exact.
  static const double _rowExtent = 72;

  final _scrollController = ScrollController();
  int? _highlightedIndex;
  Timer? _highlightTimer;

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrent() {
    final c = context.read<PlayerController>();
    final current = c.player.currentIndex;
    if (current == null || current < 0 || current >= c.queue.length) return;

    _highlightTimer?.cancel();
    setState(() => _highlightedIndex = current);
    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _highlightedIndex = null);
    });

    // Rows have a fixed extent, so the current index maps directly to an
    // offset. Center the row and clamp to the scrollable range.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final target =
          (current * _rowExtent - (pos.viewportDimension - _rowExtent) / 2)
              .clamp(0.0, pos.maxScrollExtent);
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlayerController>();
    final current = c.player.currentIndex;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Playing queue'),
        actions: [
          IconButton(
            tooltip: c.shuffled ? 'Turn shuffle off' : 'Turn shuffle on',
            color: c.shuffled ? cs.primary : null,
            icon: Opacity(
              opacity: c.shuffled ? 1 : 0.45,
              child: const Icon(Icons.shuffle),
            ),
            onPressed: () async {
              await c.toggleShuffle();
              if (mounted) _scrollToCurrent(); // show the new order
            },
          ),
          IconButton(
            tooltip: c.player.loopMode == LoopMode.off ? 'Turn loop on' : 'Turn loop off',
            color: c.player.loopMode == LoopMode.off ? null : cs.primary,
            icon: Opacity(
              opacity: c.player.loopMode == LoopMode.off ? 0.45 : 1,
              child: Icon(c.player.loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat),
            ),
            onPressed: c.cycleLoop,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(
              children: [
                Text('${(current == null || c.queue.isEmpty) ? 0 : current + 1}/${c.queue.length}'),
                const Spacer(),
                IconButton(
                  tooltip: 'Select songs',
                  icon: const Icon(Icons.checklist),
                  onPressed: null,
                ),
                IconButton(
                  tooltip: 'Clear queue',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: c.queue.isEmpty ? null : c.clearQueue,
                ),
              ],
            ),
          ),
          Expanded(
            child: c.queue.isEmpty
                ? const Center(child: Text('The queue is empty'))
                : ReorderableListView.builder(
              key: const PageStorageKey<String>('playing-queue'),
              scrollController: _scrollController,
              itemExtent: _rowExtent,
              buildDefaultDragHandles: false,
              itemCount: c.queue.length,
              // onReorderItem already passes the adjusted target index.
              onReorderItem: (from, to) => c.moveInQueue(from, to),
              itemBuilder: (context, i) {
                final t = c.queue[i];
                final playing = current == i;
                  final highlighted = _highlightedIndex == i;
                return Dismissible(
                  key: ValueKey('${t.path}-$i'),
                  direction: DismissDirection.startToEnd,
                  onDismissed: (_) => c.removeFromQueue(i),
                  background: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Icon(
                      Icons.remove_circle_outline,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      color: highlighted
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Colors.transparent,
                      child: ListTile(
                    leading: TrackArtwork(bytes: t.artwork, playing: playing),
                    title: Text(t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: playing
                            ? const TextStyle(color: Colors.yellow)
                            : null),
                    subtitle: t.artist == null
                        ? null
                        : Text(t.artist!,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => c.jumpTo(i),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.more_vert),
                        onPressed: () => showTrackOptions(context, t),
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                    ]),
                  ),
                    ),
                );
              },
            ),
          ),
          if (c.current != null)
            MiniPlayer(
              trailing: IconButton(
                tooltip: 'Scroll to currently playing song',
                icon: const Icon(Icons.my_location),
                onPressed: _scrollToCurrent,
              ),
            ),
        ],
      ),
    );
  }
}
