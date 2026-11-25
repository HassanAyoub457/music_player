import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'player_controller.dart';
import 'track_menu.dart';
import 'track_artwork.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  // String q = '';
  bool favsOnly = false;
  TextEditingController q = TextEditingController(text: '');
  final Set<String> selectedPaths = {};

  void _toggleSelection(String path) {
    setState(() {
      if (!selectedPaths.add(path)) selectedPaths.remove(path);
    });
  }

  void _exitSelection() => setState(selectedPaths.clear);

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlayerController>();
    final list = c.library
        .where(
          (t) =>
              !c.hiddenTracks.contains(t.path) &&
              (!favsOnly || c.favorites.contains(t.path)) &&
              (t.title.toLowerCase().contains(q.text.toLowerCase()) || (t.artist ?? '').toLowerCase().contains(q.text.toLowerCase())),
        )
        .toList();

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: q,
              onChanged: (v) => setState(() => q.text = v),
              decoration: InputDecoration(
                hintText: 'Search songs',
                prefixIcon: const Icon(Icons.search),
                // suffixIcon: IconButton(
                //   icon: Icon(favsOnly ? Icons.favorite : Icons.favorite_border),
                //   tooltip: 'Favorites only',
                //   onPressed: () => setState(() => favsOnly = !favsOnly),
                // ),
                suffixIcon: q.text.isNotEmpty ? IconButton(onPressed: () => setState(() => q.clear()), icon: Icon(Icons.clear)) : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (selectedPaths.isNotEmpty) ...[
                  IconButton(tooltip: 'Cancel selection', icon: const Icon(Icons.close), onPressed: _exitSelection),
                  Text('${selectedPaths.length} selected'),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Hide selected songs',
                    icon: const Icon(Icons.visibility_off_outlined),
                    onPressed: () async {
                      final selected = c.library.where((track) => selectedPaths.contains(track.path)).toList();
                      await c.hideTracks(selected);
                      if (mounted) _exitSelection();
                    },
                  ),
                ] else ...[
                  Text('${list.length} songs'),
                  const Spacer(),
                  TextButton.icon(onPressed: list.isEmpty ? null : () => c.playShuffled(list), icon: const Icon(Icons.shuffle), label: const Text('Shuffle play')),
                ],
              ],
            ),
          ),
          Expanded(
            child: c.scanning
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: c.scan,
                    child: list.isEmpty
                        ? ListView(
                            children: const [
                              Padding(
                                padding: EdgeInsets.all(48),
                                child: Center(child: Text('No songs found.\nDownload some in the Download tab, or pull to rescan.', textAlign: TextAlign.center)),
                              ),
                            ],
                          )
                        : ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final t = list[i];
                              final playing = c.current?.path == t.path;
                              final selected = selectedPaths.contains(t.path);
                              return ListTile(
                                selected: selected,
                                selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
                                leading: selected ? const CircleAvatar(child: Icon(Icons.check)) : TrackArtwork(bytes: t.artwork, playing: playing),
                                title: Text(
                                  t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: playing ? const TextStyle(color: Colors.yellow) : null,
                                ),
                                subtitle: t.artist == null ? null : Text(t.artist!, maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: selectedPaths.isEmpty ? IconButton(icon: const Icon(Icons.more_vert), onPressed: () => showTrackOptions(context, t)) : null,
                                onTap: () => selectedPaths.isNotEmpty ? _toggleSelection(t.path) : c.playQueue(list, i),
                                onLongPress: () => _toggleSelection(t.path),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
