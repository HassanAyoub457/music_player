import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';

import 'downloader.dart';
import 'download_page.dart';
import 'library_page.dart';
import 'perf_logger.dart';
import 'player_controller.dart';
import 'playlists_page.dart';
import 'theme.dart';
import 'track_artwork.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PerfLog.start(); // frame timing CSV (profile/debug only)
  await JustAudioBackground.init(androidNotificationChannelId: 'com.example.seal_player.audio', androidNotificationChannelName: 'Playback', androidNotificationOngoing: true);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlayerController()..init()),
        ChangeNotifierProvider(create: (_) => Downloader()),
      ],
      child: MaterialApp(
        title: 'Seal Player',
        themeMode: ThemeMode.dark,
        theme: AppTheme.dark(),
        // One gradient behind every page; scaffolds are transparent.
        builder: (context, child) => flatBg
            ? ColoredBox(color: const Color(0xFF2A0F2E), child: child)
            : DecoratedBox(
                decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
                child: child,
              ),
        home: const Home(),
      ),
    ),
  );
}

/// Profiling switch: `--dart-define=FLAT_BG=true` swaps the app-wide gradient
/// for a solid colour so its GPU cost can be measured.
const bool flatBg = bool.fromEnvironment('FLAT_BG');

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;

  @override
  void initState() {
    super.initState();
    final player = context.read<PlayerController>();
    context.read<Downloader>().onFinished = player.scan;
    PerfLog.attach(player.player);
    PerfLog.mark('config FLAT_BG=$flatBg ART_THUMBS=${PlayerController.useThumbs} DISC_HZ=$kDiscHz');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: tab, children: const [LibraryPage(), PlaylistsPage(), DownloadPage()]),
    bottomNavigationBar: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const MiniPlayer(),
        NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.library_music), label: 'Library'),
            NavigationDestination(icon: Icon(Icons.queue_music), label: 'Playlists'),
            NavigationDestination(icon: Icon(Icons.download), label: 'Download'),
          ],
        ),
      ],
    ),
  );
}
