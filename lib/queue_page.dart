import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'player_controller.dart';

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
              onReorder: (from, to) {
                if (to > from) to -= 1;
                c.moveInQueue(from, to);
              },
              itemBuilder: (_, i) {
                final t = c.queue[i];
                final playing = current == i;
                return ListTile(
                  key: ObjectKey(t),
                  leading: Icon(playing ? Icons.equalizer : Icons.music_note,
                      color: playing
                          ? Theme.of(context).colorScheme.primary
                          : null),
                  title: Text(t.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: t.artist == null
                      ? null
                      : Text(t.artist!,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => c.jumpTo(i),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Remove from queue',
                      onPressed: () => c.removeFromQueue(i),
                    ),
                    ReorderableDragStartListener(
                      index: i,
                      child: const Icon(Icons.drag_handle),
                    ),
                  ]),
                );
              },
            ),
    );
  }
}
