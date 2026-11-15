import 'package:cns/home.dart';
import 'package:cns/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A narrow phone, as the 375 px of the web tests
  Future<void> openApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const CnsApp());
  }

  String selectedPage(WidgetTester tester) =>
      cnsPages[tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex].label;

  Finder menuItem(String label) => find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

  testWidgets('il titolo e le quattro voci del menu, come il web', (tester) async {
    await openApp(tester);
    expect(find.text('CNS'), findsOneWidget);
    expect(find.text('Chi Ni Sentimu'), findsOneWidget);
    for (final label in ['Controllare', 'Recuperando', 'Novità', 'Impostazioni']) {
      expect(menuItem(label), findsOneWidget);
    }
    expect(selectedPage(tester), 'Controllare');
    expect(tester.takeException(), isNull); // nothing overflows on a narrow phone
  });

  testWidgets('toccando una voce del menu si apre la sua pagina', (tester) async {
    await openApp(tester);
    await tester.tap(menuItem('Novità'));
    await tester.pumpAndSettle();
    expect(selectedPage(tester), 'Novità');
    expect(find.text('Le uscite nuove degli artisti che controlli, e quelle in arrivo.'), findsOneWidget);
    await tester.tap(menuItem('Impostazioni'));
    await tester.pumpAndSettle();
    expect(find.text('Account, notifiche, persone ammesse e copia di sicurezza.'), findsOneWidget);
  });

  testWidgets('scorrendo con il dito si passa alla pagina accanto', (tester) async {
    await openApp(tester);
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(selectedPage(tester), 'Recuperando');
    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(selectedPage(tester), 'Controllare');
  });

  testWidgets('i testi di Flutter sono in italiano', (tester) async {
    await openApp(tester);
    final context = tester.element(find.byType(HomeShell));
    expect(MaterialLocalizations.of(context).cancelButtonLabel, 'Annulla');
  });
}
