import 'package:cns/data/artists.dart';
import 'package:cns/data/segnalibro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  // League of Legends, a few real titles (as the web tests)
  List<dynamic> lol() => [
        release('Warriors', '2014-09-19'),
        release('Legends Never Die', '2017-09-21'),
        release('Legends Never Die (Remix)', '2018-01-10'),
        release('RISE', '2018-09-24'),
        release('Worlds Collection', '2022-01-01', 'compile'),
      ];

  Future<TestApp> openArtist(WidgetTester tester, String lista, {Map<String, dynamic> extra = const {}}) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = TestApp();
    app.artistsBackend.put('capo', '80', {'nome': 'League of Legends', 'lista': lista, 'fan': 1200000, 'nota': '', ...extra});
    app.deezer.discographies['80'] = [...lol().cast()];
    await tester.pumpWidget(app.widget);
    await tester.tap(find.text('Accedi con Google'));
    await tester.pumpAndSettle();
    if (lista != Lists.controllare) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Recuperando')));
      await tester.pumpAndSettle();
    }
    if (lista == Lists.archivio) {
      await tester.tap(find.textContaining('Archivio ('));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('League of Legends'));
    await tester.pumpAndSettle();
    return app;
  }

  Fatte fatte(TestApp app) => app.artistsBackend.saved('capo', '80')!.fatte;

  testWidgets('Recuperando: la lista mostra il punto del segnalibro', (tester) async {
    final app = await openArtist(tester, Lists.recuperando, extra: {
      'fatte': {'single|warriors': {'s': 'a', 't': 1}},
    });
    await tester.tap(find.byTooltip('Indietro'));
    await tester.pumpAndSettle();
    expect(find.text('1 di 3 · prossima: Legends Never Die'), findsOneWidget);
    expect(app.deezer.discographyCalls, ['80']); // una sola volta: poi la copia
  });

  testWidgets('segnalibro: Ascoltato, Salta, Annulla e la fine della discografia', (tester) async {
    final app = await openArtist(tester, Lists.recuperando);
    expect(find.text('Prossima da ascoltare'), findsOneWidget);
    expect(find.text('0 di 3 (0%) · ascoltate 0, saltate 0'), findsOneWidget); // la raccolta e il remix non contano

    await tester.tap(find.text('Ascoltato'));
    await tester.pumpAndSettle();
    expect(fatte(app)['single|warriors']!.state, listened);
    expect(find.text('1 di 3 (33%) · ascoltate 1, saltate 0'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Salta'));
    await tester.pumpAndSettle();
    expect(fatte(app)['single|legends never die']!.state, skipped);

    await tester.tap(find.text('Annulla l’ultimo'));
    await tester.pumpAndSettle();
    expect(fatte(app).containsKey('single|legends never die'), isFalse);

    // Ascoltato due volte: fine della discografia, con le tre scelte
    await tester.tap(find.text('Ascoltato'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ascoltato'));
    await tester.pumpAndSettle();
    expect(find.text('Hai finito la discografia di League of Legends 🎉'), findsOneWidget);
    await tester.tap(find.text('Tieni qui'));
    await tester.pumpAndSettle();
    expect(app.artistsBackend.saved('capo', '80')!.fineTenuta, isTrue);
    expect(find.text('Discografia finita 🎉'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Arrivato qui» nella discografia, e «annulla» su una sola uscita', (tester) async {
    final app = await openArtist(tester, Lists.recuperando);
    // The «Arrivato qui» of the row of Legends Never Die (the rows above may not be built)
    final row = find.ancestor(
      of: find.text('Legends Never Die'),
      matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration
          && (w.decoration as BoxDecoration).border != null),
    );
    await tester.scrollUntilVisible(find.text('Legends Never Die'), 300, scrollable: find.byType(Scrollable).first);
    final upTo = find.descendant(of: row.first, matching: find.text('Arrivato qui'));
    await tester.ensureVisible(upTo);
    await tester.pumpAndSettle();
    await tester.tap(upTo); // also Warriors, before it
    await tester.pumpAndSettle();
    expect(fatte(app).keys.toSet(), {'single|warriors', 'single|legends never die'});
    // The «annulla» of the row of Warriors
    final warriorsRow = find.ancestor(
      of: find.text('Warriors'),
      matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration
          && (w.decoration as BoxDecoration).border != null),
    );
    await tester.scrollUntilVisible(find.text('Warriors'), -300, scrollable: find.byType(Scrollable).first);
    final undo = find.descendant(of: warriorsRow.first, matching: find.text('annulla'));
    await tester.ensureVisible(undo);
    await tester.pumpAndSettle();
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(fatte(app).keys, ['single|legends never die']);
  });

  testWidgets('con «sposta in automatico», finire la discografia porta in Controllare', (tester) async {
    final app = await openArtist(tester, Lists.recuperando, extra: {
      'auto_sposta': true,
      'tipi_recupero': ['single'],
      'fatte': {
        'single|warriors': {'s': 'a', 't': 1},
        'single|legends never die': {'s': 'a', 't': 2},
      },
    });
    await tester.tap(find.text('Ascoltato'));
    await tester.pumpAndSettle();
    expect(app.artistsBackend.saved('capo', '80')!.lista, Lists.controllare);
    expect(find.text('Discografia finita: League of Legends è passato in Controllare.'), findsOneWidget);
  });

  testWidgets('Controllare: gli avvisi per tipo, almeno uno', (tester) async {
    final app = await openArtist(tester, Lists.controllare);
    expect(find.text('Avvisi'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Raccolte'));
    await tester.pumpAndSettle();
    expect(app.artistsBackend.saved('capo', '80')!.tipiAvviso, ['album', 'ep', 'single', 'featuring']);
    for (final k in ['Album', 'EP', 'Singoli']) {
      await tester.tap(find.widgetWithText(FilterChip, k));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.widgetWithText(FilterChip, 'Featuring')); // l'ultimo: non si toglie
    await tester.pumpAndSettle();
    expect(app.artistsBackend.saved('capo', '80')!.tipiAvviso, ['featuring']);
    expect(find.textContaining('Lascia almeno un tipo'), findsOneWidget);
  });

  testWidgets('la nota si salva quando si esce dalla casella', (tester) async {
    final app = await openArtist(tester, Lists.controllare);
    await tester.enterText(find.byType(TextField), '  aspetto il nuovo album ');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(app.artistsBackend.saved('capo', '80')!.nota, 'aspetto il nuovo album');
    expect(find.text('Nota salvata.'), findsOneWidget);
  });

  testWidgets('la discografia: versioni unite, filtro per tipo, ordine', (tester) async {
    await openArtist(tester, Lists.controllare);
    await tester.scrollUntilVisible(find.text('+1 versione'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Tutte 4'), findsOneWidget);
    expect(find.text('Singoli 3'), findsOneWidget);
    expect(find.text('Raccolte 1'), findsOneWidget);
    expect(find.text('+1 versione'), findsOneWidget); // il remix sotto Legends Never Die
    expect(find.text('Dalla più recente'), findsOneWidget); // in Controllare prima le nuove
    await tester.tap(find.text('Raccolte 1'));
    await tester.pumpAndSettle();
    expect(find.text('Warriors'), findsNothing);
    expect(find.text('Worlds Collection'), findsOneWidget);
  });

  testWidgets('Deezer non risponde: messaggio e Riprova; con la copia salvata la mostra', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = TestApp();
    app.artistsBackend.put('capo', '80', {'nome': 'League of Legends', 'lista': Lists.controllare, 'nota': ''});
    app.deezer.down = true;
    await tester.pumpWidget(app.widget);
    await tester.tap(find.text('Accedi con Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('League of Legends'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Riprova'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Discografia non caricata'), findsOneWidget);

    app.deezer
      ..down = false
      ..discographies['80'] = [...lol().cast()];
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('Tutte 4'), findsOneWidget);
    expect(app.cache.saved['80']!.$1.length, 5); // la copia sul telefono

    // Sei ore dopo Deezer non risponde: resta la copia, con l'avviso
    app.clock = app.clock.add(const Duration(hours: 7));
    app.deezer.down = true;
    app.discos.ensure('80');
    await tester.pumpAndSettle();
    expect(find.text('Tutte 4'), findsOneWidget);
    expect(find.text('Deezer non risponde: è la copia salvata'), findsOneWidget);
  });
}
