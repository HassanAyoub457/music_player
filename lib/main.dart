import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'downloader.dart';
import 'download_page.dart';
import 'library_page.dart';
import 'player_controller.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.seal_player.audio',
    androidNotificationChannelName: 'Playback',
    androidNotificationOngoing: true,
  );
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => PlayerController()..init()),
      ChangeNotifierProvider(create: (_) => Downloader()),
    ],
    child: MaterialApp(
      title: 'Seal Player',
      themeMode: ThemeMode.system,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: Colors.teal,
          brightness: Brightness.dark,
          useMaterial3: true),
      home: const Home(),
    ),
  ));
}

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
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(
            index: tab, children: const [LibraryPage(), DownloadPage()]),
        bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() => tab = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.library_music), label: 'Library'),
              NavigationDestination(
                  icon: Icon(Icons.download), label: 'Download'),
            ],
          ),
        ]),
      );
}
