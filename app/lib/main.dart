import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'state/cover_store.dart';
import 'state/downloads.dart';
import 'state/library.dart';
import 'state/player.dart';
import 'state/session.dart';
import 'state/settings.dart';
import 'ui/login_screen.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'state/updates.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final settings = AppSettings();
  await settings.load();
  final session = Session();
  await session.restore();
  final library = Library(session);
  final downloads = Downloads(session);
  await downloads.init();
  final covers = CoverStore(session);
  await covers.init();
  downloads.onEnsure = (b) => covers.fetch(b.id, full: true);
  await PlayerController.configureSession();
  final player = await AudioService.init(
    builder: () => PlayerController(library, downloads),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'org.heidsiek.hoerwerk.playback',
      androidNotificationChannelName: 'Wiedergabe',
      // Stay a foreground service while paused. Otherwise Android freezes the
      // app after a few minutes and the notification, lock screen and car
      // controls stop responding. A long pause releases it (player.dart).
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      rewindInterval: Duration(seconds: 15),
      fastForwardInterval: Duration(seconds: 30),
      // Android Auto: shelves as a list, books as a grid of covers.
      androidBrowsableRootExtras: {
        'android.media.browse.CONTENT_STYLE_SUPPORTED': true,
        'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT': 1,
        'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT': 2,
        'android.media.browse.SEARCH_SUPPORTED': true,
      },
    ),
  );
  library.addListener(() => downloads.registerBooks(library.books));
  final update = AppUpdate(session);
  library.onRefreshed = (books) {
    covers.prefetch(books);
    update.check(); // at most every 10 minutes
  };
  update.check(force: true);
  if (session.loggedIn) await library.open();
  player.restoreLast();

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider.value(value: library),
      ChangeNotifierProvider.value(value: downloads),
      ChangeNotifierProvider.value(value: covers),
      ChangeNotifierProvider.value(value: player),
      ChangeNotifierProvider.value(value: update),
    ],
    child: const SuperPapageiApp(),
  ));
}

class SuperPapageiApp extends StatefulWidget {
  const SuperPapageiApp({super.key});
  @override
  State<SuperPapageiApp> createState() => _SuperPapageiAppState();
}

class _SuperPapageiAppState extends State<SuperPapageiApp> with WidgetsBindingObserver {
  bool? _wasLoggedIn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final player = context.read<PlayerController>();
    final library = context.read<Library>();
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      player.flush();
    } else if (state == AppLifecycleState.resumed) {
      library.sync();
      context.read<Downloads>().resumeWanted();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    if (_wasLoggedIn == true && !session.loggedIn) {
      // Logged out (by the user or because the token was revoked).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<PlayerController>().unload();
        context.read<Library>().close();
      });
    }
    _wasLoggedIn = session.loggedIn;
    return MaterialApp(
      title: 'Super-Papagei',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: context.watch<AppSettings>().themeMode,
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: session.loggedIn ? const Shell() : const LoginScreen(),
    );
  }
}
