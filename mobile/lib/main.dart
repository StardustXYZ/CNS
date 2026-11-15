import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/account.dart';
import 'data/artists.dart';
import 'data/deezer.dart';
import 'data/firebase_account.dart';
import 'data/firebase_artists.dart';
import 'home.dart';
import 'pages/account_pages.dart';
import 'pages/list_pages.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AccountBackend? accountBackend;
  ArtistsBackend? artistsBackend;
  try {
    await Firebase.initializeApp(); // from android/app/google-services.json
    accountBackend = FirebaseAccountBackend();
    artistsBackend = FirebaseArtistsBackend();
  } catch (err) {
    debugPrint('Firebase non avviato: $err'); // the access screen says that the account is not available
  }
  final account = AccountStore(accountBackend);
  runApp(CnsApp(account: account, artists: ArtistStore(account, artistsBackend), deezer: DeezerClient()));
}

/// CNS (Chi Ni Sentimu): the releases of the artists you follow, on the phone.
class CnsApp extends StatelessWidget {
  const CnsApp({super.key, required this.account, required this.artists, required this.deezer});

  // With fakes in the tests
  final AccountStore account;
  final ArtistStore artists;
  final DeezerApi deezer;

  @override
  Widget build(BuildContext context) {
    // Above the navigator: the pages opened on top (search, import…) see them too
    return AccountScope(
      store: account,
      child: ArtistsScope(
        store: artists,
        child: DeezerScope(
          api: deezer,
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
    );
  }
}
