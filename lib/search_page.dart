import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'downloader.dart';

/// Search YouTube (through yt-dlp) and download a result with one tap.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final query = TextEditingController();
  bool audio = true;
  String format = 'mp3';

  List<SearchResult> results = [];
  bool searching = false;
  String? searchError;
  final jobFor = <String, String>{}; // result id -> download job id
  final starting = <String>{}; // results whose download is being handed over

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> _search(Downloader d) async {
    final q = query.text.trim();
    if (q.isEmpty || searching || !d.ready) return;
    FocusScope.of(context).unfocus();
    setState(() {
      searching = true;
      searchError = null;
    });
    try {
      final r = await d.search(q);
      if (!mounted) return;
      setState(() {
        results = r;
        if (r.isEmpty) searchError = 'No results for "$q".';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        results = [];
        searchError = 'Search failed: ${e.message}';
      });
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  String _duration(double? seconds) {
    if (seconds == null) return 'Live';
    final s = seconds.round();
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
  }

  Future<void> _download(Downloader d, SearchResult r) async {
    if (starting.contains(r.id)) return;
    setState(() => starting.add(r.id));
    final jobId = await d.start(r.url, audio: audio, format: format, title: r.title);
    if (!mounted) return;
    setState(() {
      starting.remove(r.id);
      jobFor[r.id] = jobId;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Downloading "${r.title}" — progress is on the Download tab'),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  /// Spinner while downloading, check when done, and a retry button if it
  /// failed or was cancelled (so a result can always be tried again).
  Widget _trailing(Downloader d, SearchResult r) {
    final job = d.jobs[jobFor[r.id]];
    final active = job != null && !job.done && !job.failed && !job.cancelled;
    if (starting.contains(r.id) || active) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: job != null && job.progress > 0 ? job.progress : null,
          ),
        ),
      );
    }
    if (job != null && job.done) {
      return const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.check_circle));
    }
    final retry = job != null; // failed or cancelled
    return IconButton(
      tooltip: retry
          ? 'Download failed \u2014 tap to retry'
          : (audio ? 'Download audio ($format)' : 'Download video'),
      icon: Icon(retry ? Icons.refresh : Icons.download),
      onPressed: d.ready ? () => _download(d, r) : null,
    );
  }

  Widget _resultTile(Downloader d, SearchResult r) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 96,
            height: 54,
            child: Image.network(
              r.thumbnail,
              fit: BoxFit.cover,
              cacheWidth: 192,
              errorBuilder: (_, __, ___) => const ColoredBox(
                color: Colors.black26,
                child: Icon(Icons.music_video),
              ),
            ),
          ),
        ),
        title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [if (r.channel.isNotEmpty) r.channel, _duration(r.duration)].join(' · '),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _trailing(d, r),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<Downloader>();
    final active = d.jobs.values.where((j) => !j.done && !j.failed && !j.cancelled).length;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (d.initError != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(padding: const EdgeInsets.all(12), child: Text('yt-dlp failed to start: ${d.initError}')),
            ),
          TextField(
            controller: query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(d),
            decoration: InputDecoration(
              labelText: d.ready ? 'Search YouTube' : 'Starting engine…',
              border: const OutlineInputBorder(),
              suffixIcon: searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: d.ready ? () => _search(d) : null,
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
          if (active > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('$active downloading — see the Download tab'),
            ),
          const SizedBox(height: 12),
          if (searchError != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(searchError!)),
          for (final r in results) _resultTile(d, r),
          if (results.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() {
                  results = [];
                  jobFor.clear();
                }),
                child: const Text('Clear results'),
              ),
            ),
        ],
      ),
    );
  }
}
