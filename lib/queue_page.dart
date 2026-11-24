import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'player_controller.dart';
import 'track_artwork.dart';
import 'track_menu.dart';

class QueuePage extends StatelessWidget {
  const QueuePage({super.key});

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
            tooltip: c.player.shuffleModeEnabled ? 'Turn shuffle off' : 'Turn shuffle on',
            color: c.player.shuffleModeEnabled ? cs.primary : null,
            icon: const Icon(Icons.shuffle),
            onPressed: c.toggleShuffle,
          ),
          IconButton(
            tooltip: c.player.loopMode == LoopMode.off ? 'Turn loop on' : 'Turn loop off',
            color: c.player.loopMode == LoopMode.off ? null : cs.primary,
            icon: Icon(c.player.loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat),
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
                Text('${current == null ? 0 : current + 1}/${c.queue.length}'),
                const Spacer(),
                IconButton(
                  tooltip: 'Select songs',
                  icon: const Icon(Icons.checklist),
                  onPressed: null,
                ),
                IconButton(
                  tooltip: 'Clear queue',
                  icon: const Icon(Icons.clear_all),
                  onPressed: c.queue.isEmpty ? null : c.clearQueue,
                ),
              ],
            ),
          ),
          Expanded(
            child: c.queue.isEmpty
                ? const Center(child: Text('The queue is empty'))
                : ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: c.queue.length,
              onReorderItem: (from, to) {
                if (to > from) to -= 1;
                c.moveInQueue(from, to);
              },
              itemBuilder: (context, i) {
                final t = c.queue[i];
                final playing = current == i;
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
                  child: ListTile(
                    leading: TrackArtwork(bytes: t.artwork, playing: playing),
                    title: Text(t.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
