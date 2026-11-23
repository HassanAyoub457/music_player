import 'package:flutter/material.dart';
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

    return Scaffold(
      appBar: AppBar(title: Text('Queue (${c.queue.length})')),
      body: c.queue.isEmpty
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
    );
  }
}
