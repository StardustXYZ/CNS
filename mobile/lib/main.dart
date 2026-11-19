import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'data/account.dart';
import 'data/artists.dart';
import 'data/backup.dart';
import 'data/deezer.dart';
import 'data/discography_store.dart';
import 'data/firebase_account.dart';
import 'data/firebase_artists.dart';
import 'data/firebase_backup.dart';
import 'data/firebase_news.dart';
import 'data/firebase_push.dart';
import 'data/home_widget_sync.dart';
import 'data/news.dart';
import 'data/notifications.dart';
import 'data/updates.dart';
import 'home.dart';
import 'pages/account_pages.dart';
import 'pages/app_info.dart' show UpdateScope;
import 'pages/impostazioni_page.dart' show BackupScope, NotificationScope, appVersion;
import 'pages/list_pages.dart';
import 'pages/novita_page.dart';
import 'pages/widgets.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AccountBackend? accountBackend;
  ArtistsBackend? artistsBackend;
  NewsBackend? newsBackend;
  BackupBackend? backupBackend;
  PushBackend? push;
  PhonesBackend? phones;
  try {
    await Firebase.initializeApp(); // from android/app/google-services.json
    accountBackend = FirebaseAccountBackend();
    artistsBackend = FirebaseArtistsBackend();
    newsBackend = FirebaseNewsBackend();
    backupBackend = FirebaseBackupBackend();
    push = FirebasePushBackend();
    phones = FirebasePhonesBackend();
  } catch (err) {
    debugPrint('Firebase non avviato: $err'); // the access screen says that the account is not available
  }
  final account = AccountStore(accountBackend);
  final deezer = DeezerClient();
  final artists = ArtistStore(account, artistsBackend);
  final news = NewsStore(account, newsBackend, FileSeenStore());
  final discographies = DiscographyStore(deezer, FileDiscoCache());
  final backup = BackupService(account, artists, news, backupBackend, PickerFiles());
  final notifications = push != null && phones != null ? NotificationStore(account, phones, push) : null;
  // The version of this APK: shown in Impostazioni and compared with the releases on GitHub
  UpdateStore? updates;
  try {
    appVersion = (await PackageInfo.fromPlatform()).version;
    updates = UpdateStore(currentVersion: appVersion);
  } catch (err) {
    debugPrint('Versione non letta: $err');
  }
  runApp(
    CnsApp(
      account: account,
      artists: artists,
      deezer: deezer,
      discographies: discographies,
      news: news,
      backup: backup,
      notifications: notifications,
      updates: updates,
    ),
  );
  // A few seconds after opening, without slowing the start
  if (updates != null) Timer(const Duration(seconds: 3), updates.check);
  // Notifications: with the app open a message at the bottom; a tap opens Novità
  if (push != null) {
    push.foreground().listen(
      (text) =>
          messengerKey.currentState?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 8))),
    );
    push.openedLinks().listen((uri) => widgetLink.value = uri);
    try {
      final opened = await push.initialLink();
      if (opened != null) widgetLink.value = opened;
    } catch (err) {
      debugPrint('Notifica di apertura non letta: $err');
    }
  }
  // The home screen widgets: their texts follow the app, a tap opens the right page
  try {
    final bridge = HomeWidgetBridge();
    WidgetSync(bridge, news, artists, discographies);
    final fromWidget = await bridge.initialLink();
    if (fromWidget != null) widgetLink.value = fromWidget; // not over the link of a notification
    bridge.links.listen((uri) => widgetLink.value = uri);
  } catch (err) {
    debugPrint('Widget non disponibili: $err');
  }
}

/// For the messages at the bottom of the screen shown from outside the pages (notifications).
final messengerKey = GlobalKey<ScaffoldMessengerState>();

/// CNS (Chi Ni Sindimu): the releases of the artists you follow, on the phone.
class CnsApp extends StatelessWidget {
  const CnsApp({
    super.key,
    required this.account,
    required this.artists,
    required this.deezer,
    required this.discographies,
    required this.news,
    required this.backup,
    this.notifications,
    this.updates,
  });

  // With fakes in the tests
  final AccountStore account;
  final ArtistStore artists;
  final DeezerApi deezer;
  final DiscographyStore discographies;
  final NewsStore news;
  final BackupService backup;
  final NotificationStore? notifications; // null without Firebase
  final UpdateStore? updates; // null in the tests

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
              child: BackupScope(
                service: backup,
                child: NotificationScope(
                  store: notifications,
                  child: UpdateScope(
                    store: updates,
                    child: MaterialApp(
                      title: 'CNS',
                      debugShowCheckedModeBanner: false,
                      scaffoldMessengerKey: messengerKey,
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
          ),
        ),
      ),
    );
  }
}
