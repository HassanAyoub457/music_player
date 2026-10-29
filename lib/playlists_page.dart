import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'player_controller.dart';
import 'track_menu.dart';

class PlaylistsPage extends StatelessWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlayerController>();
    final names = c.playlists.keys.toList();

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text('Playlists', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.add),
                  label: const Text('New'),
                  onPressed: () async {
                    final n = await askName(context, title: 'New playlist', action: 'Create');
                    if (n == null) return;
                    final ok = await c.createPlaylist(n);
                    if (!ok && context.mounted) {
                      toast(context, 'Name is empty or already used');
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: names.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No playlists yet.\nTap New, or use ⋮ on a song → Add to playlist.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: names.length,
                    itemBuilder: (_, i) {
                      final n = names[i];
                      return ListTile(
                        leading: const Icon(Icons.queue_music),
                        title: Text(n),
                        subtitle: Text('${c.tracksOf(n).length} songs'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => PlaylistDetailPage(name: n)),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'rename') {
                              final nn = await askName(
                                context,
                                title: 'Rename playlist',
                                initial: n,
                              );
                              if (nn == null || nn == n) return;
                              final ok = await c.renamePlaylist(n, nn);
                              if (!ok && context.mounted) {
                                toast(context, 'Name is empty or already used');
                              }
                            } else if (v == 'delete') {
                              if (await confirm(context, 'Delete playlist?', n, 'Delete')) {
                                await c.deletePlaylist(n);
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'play', child: Text('Play')),
                            PopupMenuItem(value: 'play_next', child: Text('Play next')),
                            PopupMenuItem(value: 'rename', child: Text('Rename')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
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

class PlaylistDetailPage extends StatelessWidget {
  final String name;
  const PlaylistDetailPage({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlayerController>();
    final tracks = c.tracksOf(name);
    void addSongs() =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => PickSongsPage(playlist: name)));

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(icon: const Icon(Icons.add), tooltip: 'Add songs', onPressed: addSongs),
        ],
      ),
      body: tracks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('This playlist is empty'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: addSongs,
                    icon: const Icon(Icons.add),
                    label: const Text('Add songs'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play'),
                        onPressed: () => c.playQueue(tracks, 0),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.shuffle),
                        label: const Text('Shuffle'),
                        onPressed: () => c.playShuffled(tracks),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: tracks.length,
                    itemBuilder: (_, i) {
                      final t = tracks[i];
                      final playing = c.current?.path == t.path;
                      return ListTile(
                        leading: Icon(
                          playing ? Icons.equalizer : Icons.music_note,
                          color: playing ? Theme.of(context).colorScheme.primary : null,
                        ),
                        title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: t.artist == null
                            ? null
                            : Text(t.artist!, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.more_vert),
                          onPressed: () => showTrackOptions(context, t, inPlaylist: name),
                        ),
                        onTap: () => c.playQueue(tracks, i),
                        onLongPress: () => showTrackOptions(context, t, inPlaylist: name),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

/// Multi-select picker for adding songs to a playlist.
class PickSongsPage extends StatefulWidget {
  final String playlist;
  const PickSongsPage({super.key, required this.playlist});
  @override
  State<PickSongsPage> createState() => _PickSongsPageState();
}

class _PickSongsPageState extends State<PickSongsPage> {
  final selected = <String>{};
  String q = '';

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlayerController>();
    final existing = c.playlists[widget.playlist] ?? const <String>[];
    final list = c.library
        .where(
          (t) =>
              t.title.toLowerCase().contains(q.toLowerCase()) ||
              (t.artist ?? '').toLowerCase().contains(q.toLowerCase()),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Add to ${widget.playlist}'),
        actions: [
          TextButton(
            onPressed: selected.isEmpty
                ? null
                : () async {
                    await c.addManyToPlaylist(widget.playlist, selected);
                    if (context.mounted) Navigator.pop(context);
                  },
            child: Text('Add (${selected.length})'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              onChanged: (v) => setState(() => q = v),
              decoration: InputDecoration(
                hintText: 'Search songs',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final t = list[i];
                final already = existing.contains(t.path);
                return CheckboxListTile(
                  value: already || selected.contains(t.path),
                  onChanged: already
                      ? null
                      : (v) => setState(
                          () => v == true ? selected.add(t.path) : selected.remove(t.path),
                        ),
                  title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: t.artist == null
                      ? null
                      : Text(t.artist!, maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
