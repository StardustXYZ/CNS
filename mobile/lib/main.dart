import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'home.dart';
import 'theme.dart';

void main() {
  runApp(const CnsApp());
}

/// CNS (Chi Ni Sentimu): the releases of the artists you follow, on the phone.
class CnsApp extends StatelessWidget {
  const CnsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CNS',
      debugShowCheckedModeBanner: false,
      theme: cnsTheme(),
      // Flutter's own texts (dates, "Annulla", "Incolla"…) in Italian
      locale: const Locale('it'),
      supportedLocales: const [Locale('it')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const HomeShell(),
    );
  }
}
