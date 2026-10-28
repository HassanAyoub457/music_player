import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'player_controller.dart';

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
        .where((t) =>
            (!favsOnly || c.favorites.contains(t.path)) &&
            t.title.toLowerCase().contains(q.toLowerCase()))
        .toList();

    return SafeArea(
      child: Column(children: [
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
          child: Row(children: [
            Text('${list.length} songs'),
            const Spacer(),
            TextButton.icon(
              onPressed: list.isEmpty ? null : () => c.playShuffled(list),
              icon: const Icon(Icons.shuffle),
              label: const Text('Shuffle play'),
            ),
          ]),
        ),
        Expanded(
          child: c.scanning
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: c.scan,
                  child: list.isEmpty
                      ? ListView(children: const [
                          Padding(
                            padding: EdgeInsets.all(48),
                            child: Center(
                                child: Text(
                                    'No songs found.\nDownload some in the Download tab, or pull to rescan.',
                                    textAlign: TextAlign.center)),
                          )
                        ])
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final t = list[i];
                            final playing = c.current?.path == t.path;
                            return ListTile(
                              leading: Icon(
                                  playing ? Icons.equalizer : Icons.music_note,
                                  color: playing
                                      ? Theme.of(context).colorScheme.primary
                                      : null),
                              title: Text(t.title,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: IconButton(
                                icon: Icon(c.favorites.contains(t.path)
                                    ? Icons.favorite
                                    : Icons.favorite_border),
                                onPressed: () => c.toggleFavorite(t),
                              ),
                              onTap: () => c.playQueue(list, i),
                              onLongPress: () => _confirmDelete(context, c, t),
                            );
                          },
                        ),
                ),
        ),
      ]),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, PlayerController c, Track t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text(t.title),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) c.delete(t);
  }
}
