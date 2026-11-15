import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/account.dart';
import 'data/artists.dart';
import 'data/deezer.dart';
import 'data/discography_store.dart';
import 'data/firebase_account.dart';
import 'data/firebase_artists.dart';
import 'data/firebase_news.dart';
import 'data/home_widget_sync.dart';
import 'data/news.dart';
import 'home.dart';
import 'pages/account_pages.dart';
import 'pages/list_pages.dart';
import 'pages/novita_page.dart';
import 'pages/widgets.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AccountBackend? accountBackend;
  ArtistsBackend? artistsBackend;
  NewsBackend? newsBackend;
  try {
    await Firebase.initializeApp(); // from android/app/google-services.json
    accountBackend = FirebaseAccountBackend();
    artistsBackend = FirebaseArtistsBackend();
    newsBackend = FirebaseNewsBackend();
  } catch (err) {
    debugPrint('Firebase non avviato: $err'); // the access screen says that the account is not available
  }
  final account = AccountStore(accountBackend);
  final deezer = DeezerClient();
  final artists = ArtistStore(account, artistsBackend);
  final news = NewsStore(account, newsBackend, FileSeenStore());
  final discographies = DiscographyStore(deezer, FileDiscoCache());
  runApp(CnsApp(account: account, artists: artists, deezer: deezer, discographies: discographies, news: news));
  // The home screen widgets: their texts follow the app, a tap opens the right page
  try {
    final bridge = HomeWidgetBridge();
    WidgetSync(bridge, news, artists, discographies);
    widgetLink.value = await bridge.initialLink();
    bridge.links.listen((uri) => widgetLink.value = uri);
  } catch (err) {
    debugPrint('Widget non disponibili: $err');
  }
}

/// CNS (Chi Ni Sentimu): the releases of the artists you follow, on the phone.
class CnsApp extends StatelessWidget {
  const CnsApp({
    super.key,
    required this.account,
    required this.artists,
    required this.deezer,
    required this.discographies,
    required this.news,
  });

  // With fakes in the tests
  final AccountStore account;
  final ArtistStore artists;
  final DeezerApi deezer;
  final DiscographyStore discographies;
  final NewsStore news;

  @override
  Widget build(BuildContext context) {
    // Above the navigator: the pages opened on top (search, import…) see them too
    return AccountScope(
      store: account,
      child: ArtistsScope(
        store: artists,
        child: DeezerScope(
          api: deezer,
          child: DiscographyScope(
            store: discographies,
            child: NewsScope(
              store: news,
              child: MaterialApp(
                title: 'CNS',
                debugShowCheckedModeBanner: false,
                theme: cnsTheme(),
                // Flutter's own texts (dates, "Annulla", "Incolla"…) in Italian
                locale: const Locale('it'),
                supportedLocales: const [Locale('it')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                home: const AccessGate(child: HomeShell()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
