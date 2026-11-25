import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'downloader.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});
  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final url = TextEditingController();
  bool audio = true;
  String format = 'mp3';

  @override
  Widget build(BuildContext context) {
    final d = context.watch<Downloader>();
    final jobs = d.jobs.values.toList().reversed.toList();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OutlinedButton.icon(
            onPressed: d.updating ? null : d.updateEngine,
            icon: const Icon(Icons.system_update_alt),
            label: Text(d.updating ? 'Updating yt-dlp…' : 'Update yt-dlp'),
          ),
          if (d.updateMessage != null) Text(d.updateMessage!),
          const SizedBox(height: 12),
          if (d.initError != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(padding: const EdgeInsets.all(12), child: Text('yt-dlp failed to start: ${d.initError}')),
            ),
          TextField(
            controller: url,
            decoration: InputDecoration(
              labelText: 'Video / audio URL',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste),
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data?.text != null) {
                    setState(() => url.text = data!.text!);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Audio'), icon: Icon(Icons.audiotrack)),
              ButtonSegment(value: false, label: Text('Video'), icon: Icon(Icons.videocam)),
            ],
            selected: {audio},
            onSelectionChanged: (s) => setState(() => audio = s.first),
          ),
          if (audio)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: DropdownButtonFormField<String>(
                initialValue: format,
                decoration: const InputDecoration(labelText: 'Audio format', border: OutlineInputBorder()),
                items: const ['mp3', 'm4a', 'opus', 'flac'].map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                onChanged: (v) => setState(() => format = v!),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: !d.ready
                ? null
                : () {
                    final u = url.text.trim();
                    if (u.isEmpty) return;
                    d.start(u, audio: audio, format: format);
                    url.clear();
                  },
            icon: const Icon(Icons.download),
            label: Text(d.ready ? 'Download' : 'Starting engine…'),
          ),
          const SizedBox(height: 16),
          if (jobs.isNotEmpty)
            Row(
              children: [
                Text('Downloads', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(onPressed: d.clearFinished, child: const Text('Clear finished')),
              ],
            ),
          for (final j in jobs)
            Card(
              child: ListTile(
                title: Text(j.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    if (!j.done && !j.failed && !j.cancelled) LinearProgressIndicator(value: j.progress > 0 ? j.progress : null),
                    const SizedBox(height: 4),
                    Text(j.status, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
                trailing: (j.done || j.failed || j.cancelled)
                    ? Icon(j.done ? Icons.check_circle : Icons.error_outline)
                    : IconButton(icon: const Icon(Icons.close), onPressed: () => d.cancel(j.id)),
              ),
            ),
        ],
      ),
    );
  }
}
