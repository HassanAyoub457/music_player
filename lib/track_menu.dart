import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'player_controller.dart';

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Text(message), duration: const Duration(seconds: 2)));
}

/// Text-input dialog that owns its controller (safe to dismiss).
class _NameDialog extends StatefulWidget {
  final String title, initial, action;
  const _NameDialog(
      {required this.title, required this.initial, required this.action});
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController ctrl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Playlist name'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: Text(widget.action)),
        ],
      );
}

Future<String?> askName(BuildContext context,
        {required String title, String initial = '', String action = 'Save'}) =>
    showDialog<String>(
        context: context,
        builder: (_) =>
            _NameDialog(title: title, initial: initial, action: action));

Future<bool> confirm(
        BuildContext context, String title, String body, String action) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    ) ??
    false;

/// The "three dots" bottom sheet for a song.
/// Pass [inPlaylist] to also offer "Remove from this playlist".
Future<void> showTrackOptions(BuildContext context, Track t,
    {String? inPlaylist}) {
  final c = context.read<PlayerController>();
  final messenger = ScaffoldMessenger.of(context);
  void say(String m) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text(m), duration: const Duration(seconds: 2)));

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) {
      Widget item(IconData icon, String label, Future<void> Function() run) =>
          ListTile(
            leading: Icon(icon),
            title: Text(label),
            onTap: () async {
              Navigator.pop(sheet);
              await run();
            },
          );
      final fav = c.favorites.contains(t.path);
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.music_note),
              title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: t.artist == null
                  ? null
                  : Text(t.artist!, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            item(Icons.playlist_play, 'Play next', () async {
              await c.playNext(t);
              say('Will play next');
            }),
            item(Icons.queue_music, 'Add to queue', () async {
              await c.addToQueue(t);
              say('Added to queue');
            }),
            item(Icons.playlist_add, 'Add to playlist', () async {
              if (context.mounted) await showAddToPlaylist(context, t);
            }),
            item(fav ? Icons.favorite : Icons.favorite_border,
                fav ? 'Remove from favorites' : 'Add to favorites', () async {
              await c.toggleFavorite(t);
            }),
            if (inPlaylist != null)
              item(Icons.remove_circle_outline, 'Remove from this playlist',
                  () async {
                await c.removeFromPlaylist(inPlaylist, t);
                say('Removed from "$inPlaylist"');
              }),
            item(Icons.delete_outline, 'Delete from device', () async {
              if (!context.mounted) return;
              final ok = await confirm(
                  context, 'Delete file?', t.title, 'Delete');
              if (ok) await c.delete(t);
            }),
          ]),
        ),
      );
    },
  );
}

Future<void> showAddToPlaylist(BuildContext context, Track t) {
  final c = context.read<PlayerController>();
  final messenger = ScaffoldMessenger.of(context);
  void say(String m) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text(m), duration: const Duration(seconds: 2)));

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) {
      final names = c.playlists.keys.toList();
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheet).size.height * 0.6),
          child: ListView(shrinkWrap: true, children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New playlist'),
              onTap: () async {
                Navigator.pop(sheet);
                if (!context.mounted) return;
                final name = await askName(context,
                    title: 'New playlist', action: 'Create');
                if (name == null) return;
                final ok = await c.createPlaylist(name, add: t);
                say(ok ? 'Added to "$name"' : 'Name is empty or already used');
              },
            ),
            for (final n in names)
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(n),
                subtitle: Text('${c.playlists[n]!.length} songs'),
                onTap: () async {
                  Navigator.pop(sheet);
                  final added = await c.addToPlaylist(n, t);
                  say(added ? 'Added to "$n"' : 'Already in "$n"');
                },
              ),
          ]),
        ),
      );
    },
  );
}
