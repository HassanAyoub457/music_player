import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'player_controller.dart';
import 'track_artwork.dart';

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Text(message), duration: const Duration(seconds: 2)));
}

/// Text-input dialog that owns its controller (safe to dismiss).
class _NameDialog extends StatefulWidget {
  final String title, initial, action;
  final String hint;
  const _NameDialog(
      {required this.title,
      required this.initial,
      required this.action,
      this.hint = 'Playlist name'});
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
          decoration: InputDecoration(hintText: widget.hint),
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
        {required String title,
        String initial = '',
        String action = 'Save',
        String hint = 'Playlist name'}) =>
    showDialog<String>(
        context: context,
        builder: (_) =>
            _NameDialog(title: title, initial: initial, action: action, hint: hint));

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
      final fav = c.favorites.contains(t.path);
      Widget sectionItem(IconData icon, String label, VoidCallback onTap) =>
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(sheet).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon),
            ),
            title: Text(label),
            onTap: onTap,
          );

      Future<void> doAction(Future<void> Function() action) async {
        Navigator.pop(sheet);
        await action();
      }
      final summary = [
        if (t.duration != null) _formatDuration(t.duration!),
        if (t.bitrate != null) '${(t.bitrate! / 1000).round()} kbps',
      ].join(' | ');

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheet).size.height * 0.88,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
              child: Row(children: [
                TrackArtwork(bytes: t.artwork, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: Theme.of(sheet).textTheme.titleSmall),
                      const SizedBox(height: 3),
                      Text(
                        summary.isEmpty
                            ? p.extension(t.path).toUpperCase().replaceFirst('.', '')
                            : summary,
                        style: Theme.of(sheet).textTheme.bodySmall?.copyWith(
                              color: Theme.of(sheet).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Details',
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => _showTrackDetails(context, t, c),
                ),
                IconButton(
                  tooltip: 'Refresh metadata',
                  icon: const Icon(Icons.refresh),
                  onPressed: () async {
                    await c.refreshTrack(t);
                    if (sheet.mounted) say('Track information refreshed');
                  },
                ),
              ]),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                sectionItem(Icons.queue_play_next, 'Play next', () => doAction(() async {
                  await c.playNext(t);
                  say('Will play next');
                })),
                sectionItem(Icons.playlist_add, 'Add to queue', () => doAction(() async {
                  await c.addToQueue(t);
                  say('Added to queue');
                })),
                sectionItem(Icons.playlist_add_circle_outlined, 'Add to playlist', () async {
                  Navigator.pop(sheet);
                  if (context.mounted) await showAddToPlaylist(context, t);
                }),
                const Divider(height: 1, indent: 16, endIndent: 16),
                sectionItem(Icons.album_outlined, 'Go to album', () => doAction(() async {
                  if (t.album == null || t.album!.isEmpty) {
                    say('No album information for this track');
                    return;
                  }
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => _RelatedTracksPage(
                      title: t.album!,
                      tracks: c.library.where((item) => item.album == t.album).toList(),
                    ),
                  ));
                })),
                sectionItem(Icons.person_outline, 'Go to artist', () => doAction(() async {
                  final artist = t.artist;
                  if (artist == null || artist.isEmpty) {
                    say('No artist information for this track');
                    return;
                  }
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => _RelatedTracksPage(
                      title: artist,
                      tracks: c.library.where((item) => item.artist == artist).toList(),
                    ),
                  ));
                })),
                const Divider(height: 1, indent: 16, endIndent: 16),
                sectionItem(Icons.label_outline, 'Edit tags', () async {
                  Navigator.pop(sheet);
                  final result = await showDialog<Map<String, String>>(
                    context: context,
                    builder: (_) => _EditTagsDialog(track: t),
                  );
                  if (result == null) return;
                  try {
                    await c.editTrackTags(
                      t,
                      title: result['title'] ?? t.title,
                      artist: result['artist'] ?? '',
                      album: result['album'] ?? '',
                      genre: result['genre'] ?? '',
                    );
                    say('Track tags updated');
                  } catch (e) {
                    say('Could not update tags: $e');
                  }
                }),
                sectionItem(Icons.image_outlined, 'Change cover', () async {
                  Navigator.pop(sheet);
                  final imagePath = await askName(
                    context,
                    title: 'Change cover',
                    initial: '',
                    action: 'Use image',
                    hint: 'Absolute path to a JPG or PNG image',
                  );
                  if (imagePath == null || imagePath.isEmpty) return;
                  try {
                    await c.editTrackCover(t, imagePath);
                    say('Cover updated');
                  } catch (e) {
                    say('Could not update cover: $e');
                  }
                }),
                sectionItem(
                    fav ? Icons.favorite : Icons.favorite_border,
                    fav ? 'Remove from favorites' : 'Add to favorites',
                    () => doAction(() async {
                    await c.toggleFavorite(t);
                  })),
                if (inPlaylist != null)
                  sectionItem(Icons.remove_circle_outline, 'Remove from this playlist',
                      () => doAction(() async {
                        await c.removeFromPlaylist(inPlaylist, t);
                        say('Removed from "$inPlaylist"');
                      })),
                sectionItem(Icons.delete_outline, 'Delete from device', () async {
                  Navigator.pop(sheet);
                  if (!context.mounted) return;
                  final confirmed = await confirm(
                    context,
                    'Delete file?',
                    t.title,
                    'Delete',
                  );
                  if (confirmed) await c.delete(t);
                }),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.pop(sheet),
                  child: const Text('CLOSE'),
                ),
              ),
            ),
          ]),
        ),
      );
    },
  );
}

Future<void> _showTrackDetails(
    BuildContext context, Track track, PlayerController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (detailsContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: FutureBuilder<FileStat>(
          future: FileStat.stat(track.path),
          builder: (context, snapshot) {
            final stat = snapshot.data;
            final fields = <(String, String)>[
              ('Title', track.title),
              ('Album', track.album ?? 'Unknown'),
              ('Artist', track.artist ?? 'Unknown'),
              ('Genre', track.genre ?? 'Unknown'),
              if (track.duration != null)
                ('Duration', _formatDuration(track.duration!)),
              ('Type', p.extension(track.path).replaceFirst('.', '').toUpperCase()),
              if (track.bitrate != null)
                ('Bitrate', '${(track.bitrate! / 1000).round()} kbps'),
              if (stat != null) ('Size', _formatFileSize(stat.size)),
              ('Location', track.path),
            ];
            return Column(mainAxisSize: MainAxisSize.min, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Details', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 18),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(children: [
                    for (final field in fields)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(width: 82, child: Text(field.$1)),
                          Expanded(child: Text(
                            field.$2,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          )),
                        ]),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: FilledButton.tonal(
                  onPressed: () => Navigator.pop(detailsContext),
                  child: const Text('CANCEL'),
                )),
                const SizedBox(width: 12),
                Expanded(child: FilledButton(
                  onPressed: () async {
                    Navigator.pop(detailsContext);
                    final result = await showDialog<Map<String, String>>(
                      context: context,
                      builder: (_) => _EditTagsDialog(track: track),
                    );
                    if (result == null) return;
                    try {
                      await controller.editTrackTags(
                        track,
                        title: result['title'] ?? track.title,
                        artist: result['artist'] ?? '',
                        album: result['album'] ?? '',
                        genre: result['genre'] ?? '',
                      );
                      toast(context, 'Track tags updated');
                    } catch (e) {
                      toast(context, 'Could not update tags: $e');
                    }
                  },
                  child: const Text('EDIT'),
                )),
              ]),
            ]);
          },
        ),
      ),
    ),
  );
}

class _EditTagsDialog extends StatefulWidget {
  final Track track;
  const _EditTagsDialog({required this.track});

  @override
  State<_EditTagsDialog> createState() => _EditTagsDialogState();
}

class _EditTagsDialogState extends State<_EditTagsDialog> {
  late final title = TextEditingController(text: widget.track.title);
  late final artist = TextEditingController(text: widget.track.artist ?? '');
  late final album = TextEditingController(text: widget.track.album ?? '');
  late final genre = TextEditingController(text: widget.track.genre ?? '');

  @override
  void dispose() {
    title.dispose();
    artist.dispose();
    album.dispose();
    genre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit tags'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
            TextField(controller: artist, decoration: const InputDecoration(labelText: 'Artist')),
            TextField(controller: album, decoration: const InputDecoration(labelText: 'Album')),
            TextField(controller: genre, decoration: const InputDecoration(labelText: 'Genre')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              'title': title.text,
              'artist': artist.text,
              'album': album.text,
              'genre': genre.text,
            }),
            child: const Text('SAVE'),
          ),
        ],
      );
}

class _RelatedTracksPage extends StatelessWidget {
  final String title;
  final List<Track> tracks;
  const _RelatedTracksPage({required this.title, required this.tracks});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView.builder(
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final track = tracks[index];
            return ListTile(
              leading: TrackArtwork(bytes: track.artwork),
              title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(track.artist ?? track.album ?? ''),
              onTap: () => context.read<PlayerController>().playQueue(tracks, index),
              trailing: IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => showTrackOptions(context, track),
              ),
            );
          },
        ),
      );
}

String _formatDuration(Duration duration) =>
    '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
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
