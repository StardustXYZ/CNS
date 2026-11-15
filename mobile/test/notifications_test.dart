import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'copia_test.dart' show settingsScroll;
import 'fakes.dart';

void main() {
  Future<TestApp> openSettings(WidgetTester tester, {void Function(TestApp app)? before}) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = TestApp();
    before?.call(app);
    await tester.pumpWidget(app.widget);
    await tester.tap(find.text('Accedi con Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Impostazioni')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Notifiche su questo telefono'), 200, scrollable: settingsScroll());
    await tester.pumpAndSettle();
    return app;
  }

  bool switchOn(WidgetTester tester) => tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value;

  testWidgets('accese: chiede il permesso e registra il telefono; spente: lo toglie', (tester) async {
    final app = await openSettings(tester, before: (app) => app.push.allowed = true);
    expect(switchOn(tester), isFalse);
    await tester.tap(find.text('Notifiche su questo telefono'));
    await tester.pumpAndSettle();
    expect(app.push.asked, ['permesso']);
    expect(app.phones.phones['capo'], {'telefono-di-prova': 'token-1'});
    expect(switchOn(tester), isTrue);
    expect(find.textContaining('Ti avviso qui'), findsOneWidget);

    // A new token from Firebase: saved again
    app.push.refresh.add('token-2');
    await tester.pumpAndSettle();
    expect(app.phones.phones['capo'], {'telefono-di-prova': 'token-2'});

    await tester.tap(find.text('Notifiche su questo telefono'));
    await tester.pumpAndSettle();
    expect(app.phones.phones['capo'], isEmpty);
    expect(switchOn(tester), isFalse);
  });

  testWidgets('senza il permesso di Android resta spento, con la spiegazione', (tester) async {
    final app = await openSettings(tester);
    await tester.tap(find.text('Notifiche su questo telefono'));
    await tester.pumpAndSettle();
    expect(switchOn(tester), isFalse);
    expect(app.phones.phones['capo'], isNull);
    expect(find.textContaining('Android non ha dato il permesso'), findsOneWidget);
  });

  testWidgets('già registrato: all’apertura risulta acceso e il token viene aggiornato', (tester) async {
    final app = await openSettings(tester, before: (app) {
      app.push
        ..granted = true
        ..currentToken = 'token-nuovo';
      app.phones.phones['capo'] = {'telefono-di-prova': 'token-vecchio'};
    });
    expect(switchOn(tester), isTrue);
    expect(app.phones.phones['capo'], {'telefono-di-prova': 'token-nuovo'});
  });

  testWidgets('permesso tolto nelle impostazioni del telefono: il telefono viene tolto e lo dice', (tester) async {
    final app = await openSettings(tester, before: (app) {
      app.phones.phones['capo'] = {'telefono-di-prova': 'token-1'};
    });
    expect(switchOn(tester), isFalse);
    expect(app.phones.phones['capo'], isEmpty);
    expect(find.textContaining('non permette più le notifiche'), findsOneWidget);
  });

  testWidgets("uscendo dall'account il telefono smette di ricevere le notifiche", (tester) async {
    final app = await openSettings(tester, before: (app) => app.push.allowed = true);
    await tester.tap(find.text('Notifiche su questo telefono'));
    await tester.pumpAndSettle();
    expect(app.phones.phones['capo'], isNotEmpty);
    await tester.scrollUntilVisible(find.text('Esci dall’account'), -200, scrollable: settingsScroll());
    await tester.tap(find.text('Esci dall’account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Esci'));
    await tester.pumpAndSettle();
    expect(app.phones.phones['capo'], isEmpty);
    expect(find.text('Accedi con Google'), findsOneWidget);
  });
}
