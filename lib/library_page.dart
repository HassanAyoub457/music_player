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
  String q = '';
  bool favsOnly = false;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlayerController>();
    final list = c.library
        .where(
          (t) =>
              (!favsOnly || c.favorites.contains(t.path)) &&
              (t.title.toLowerCase().contains(q.toLowerCase()) || (t.artist ?? '').toLowerCase().contains(q.toLowerCase())),
        )
        .toList();

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              onChanged: (v) => setState(() => q = v),
              decoration: InputDecoration(
                hintText: 'Search songs',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: Icon(favsOnly ? Icons.favorite : Icons.favorite_border),
                  tooltip: 'Favorites only',
                  onPressed: () => setState(() => favsOnly = !favsOnly),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('${list.length} songs'),
                const Spacer(),
                TextButton.icon(
                  onPressed: list.isEmpty ? null : () => c.playShuffled(list),
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Shuffle play'),
                ),
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
                                child: Center(
                                  child: Text('No songs found.\nDownload some in the Download tab, or pull to rescan.', textAlign: TextAlign.center),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final t = list[i];
                              final playing = c.current?.path == t.path;
                              return ListTile(
                                leading: TrackArtwork(bytes: t.artwork, playing: playing),
                                title: Text(
                                  t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: playing ? const TextStyle(color: Colors.yellow) : null,
                                ),
                                subtitle: t.artist == null ? null : Text(t.artist!, maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: () => showTrackOptions(context, t)),
                                onTap: () => c.playQueue(list, i),
                                onLongPress: () => showTrackOptions(context, t),
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
