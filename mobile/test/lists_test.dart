import 'package:cns/data/artists.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  Future<TestApp> openApp(WidgetTester tester, {void Function(TestApp app)? before}) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = TestApp();
    before?.call(app);
    await tester.pumpWidget(app.widget);
    await tester.tap(find.text('Accedi con Google'));
    await tester.pumpAndSettle();
    return app;
  }

  Finder menu(String label) => find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

  void seed(TestApp app, List<(String, String, String)> artists) {
    app.artistsBackend.docs['capo'] = {
      for (final (id, nome, lista) in artists) id: SavedArtist(id: id, nome: nome, lista: lista, fan: 1200000),
    };
  }

  testWidgets('le liste in ordine di nome, l\'archivio sotto Recuperando, i contatori nel menu', (tester) async {
    await openApp(tester, before: (app) => seed(app, [
          ('1', 'Zucchero', Lists.controllare),
          ('2', 'ávalanche', Lists.controllare),
          ('3', 'Måneskin', Lists.recuperando),
          ('4', 'Queen', Lists.archivio),
        ]));
    final names = tester.widgetList<ListTile>(find.byType(ListTile)).map((t) => (t.title as Text).data).toList();
    expect(names, ['ávalanche', 'Zucchero']);
    expect(find.text('1,2 mln di fan'), findsNWidgets(2));
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('2')), findsOneWidget);
    await tester.tap(menu('Recuperando'));
    await tester.pumpAndSettle();
    expect(find.text('Måneskin'), findsOneWidget);
    expect(find.text('Archivio (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lista vuota: il messaggio e i pulsanti per aggiungere', (tester) async {
    await openApp(tester);
    expect(find.text('Nessun artista da controllare per ora.'), findsOneWidget);
    expect(find.text('Aggiungi artista'), findsOneWidget);
    expect(find.text('Importa'), findsOneWidget);
  });

  testWidgets('cerca e aggiungi; poi "Già in lista", e "Sposta qui" da un\'altra lista', (tester) async {
    final app = await openApp(tester);
    await tester.tap(find.text('Aggiungi artista'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Amy Lee');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    // Il nome esatto con più fan viene prima di "Amy Leeds"
    final names = tester
        .widgetList<Text>(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').startsWith('Amy Lee')))
        .map((t) => t.data)
        .toList();
    expect(names.first, 'Amy Lee');
    await tester.tap(find.widgetWithText(FilledButton, 'Aggiungi').first);
    await tester.pumpAndSettle();
    expect(app.artistsBackend.docs['capo']!['15741']!.lista, Lists.controllare);
    expect(find.text('Già in lista ✓'), findsOneWidget);

    // Lo stesso artista cercato da Recuperando: "Sposta qui"
    await tester.tap(find.byTooltip('Indietro')); // the back arrow, in Italian
    await tester.pumpAndSettle();
    await tester.tap(menu('Recuperando'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aggiungi artista'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://www.deezer.com/it/artist/15741');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.textContaining('in Controllare'), findsOneWidget);
    await tester.tap(find.text('Sposta qui'));
    await tester.pumpAndSettle();
    expect(app.artistsBackend.docs['capo']!['15741']!.lista, Lists.recuperando);
  });

  testWidgets('dalla scheda dell\'artista: sposta in un\'altra lista e togli con conferma', (tester) async {
    final app = await openApp(tester, before: (app) => seed(app, [('27', 'Daft Punk', Lists.controllare)]));
    await tester.tap(find.text('Daft Punk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sposta in Archivio'));
    await tester.pumpAndSettle();
    expect(app.artistsBackend.docs['capo']!['27']!.lista, Lists.archivio);
    await tester.tap(menu('Recuperando'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archivio (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daft Punk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Togli dalle liste'));
    await tester.pumpAndSettle();
    expect(find.text('Togliere Daft Punk?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Togli'));
    await tester.pumpAndSettle();
    expect(app.artistsBackend.docs['capo'], isEmpty);
  });

  testWidgets("importa da un elenco: controllo, spunte e destinazione", (tester) async {
    final app = await openApp(tester, before: (app) => seed(app, [('13', 'Eminem', Lists.controllare)]));
    await tester.tap(find.text('Importa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elenco di nomi'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Amy Lee\nDaft\nEminem\nNessuno Così');
    await tester.tap(find.text('Cerca su Deezer'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.text('Trovati 2 artisti nuovi. 1 sono già nelle tue liste e li salto. 1 non trovati.'), findsOneWidget);
    expect(find.text('Hai scritto “Daft” · 4 mln di fan'), findsOneWidget);
    expect(find.text('Aggiungi 1 artisti'), findsOneWidget); // "Daft Punk" è senza spunta
    await tester.tap(find.text('Daft Punk'));
    await tester.pump();
    await tester.tap(find.text('In Recuperando'));
    await tester.pump();
    await tester.tap(find.text('Aggiungi 2 artisti'));
    await tester.pumpAndSettle();
    final saved = app.artistsBackend.docs['capo']!;
    expect(saved['15741']!.lista, Lists.recuperando);
    expect(saved['27']!.lista, Lists.recuperando);
    expect(saved['13']!.lista, Lists.controllare); // già salvato: non spostato
    expect(app.artistsBackend.writes, 1); // tutti insieme
    expect(find.text('Aggiunti 2 artisti a Recuperando.'), findsOneWidget);
  });

  testWidgets('importa da un profilo privato: il messaggio spiega cosa fare', (tester) async {
    await openApp(tester);
    await tester.tap(find.text('Importa'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://www.deezer.com/it/profile/1');
    await tester.tap(find.text('Cerca su Deezer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('forse è privato'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
