import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/account.dart';
import 'data/firebase_account.dart';
import 'home.dart';
import 'pages/account_pages.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AccountBackend? backend;
  try {
    await Firebase.initializeApp(); // from android/app/google-services.json
    backend = FirebaseAccountBackend();
  } catch (err) {
    debugPrint('Firebase non avviato: $err'); // the access screen says that the account is not available
  }
  runApp(CnsApp(account: AccountStore(backend)));
}

/// CNS (Chi Ni Sentimu): the releases of the artists you follow, on the phone.
class CnsApp extends StatelessWidget {
  const CnsApp({super.key, required this.account});

  final AccountStore account; // with a fake backend in the tests

  @override
  Widget build(BuildContext context) {
    // Above the navigator: the pages opened on top (Persone ammesse…) see the account too
    return AccountScope(
      store: account,
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
    );
  }
}
