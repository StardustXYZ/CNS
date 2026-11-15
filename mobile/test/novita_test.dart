import 'dart:async';

import 'package:cns/data/artists.dart';
import 'package:cns/data/discography_store.dart';
import 'package:cns/data/home_widget_sync.dart';
import 'package:cns/data/news.dart';
import 'package:cns/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

NewsItem novita(String id, String titolo, String artista, String artistaId, DateTime when, {String data = '2026-11-14'}) =>
    NewsItem(
      id: id,
      titolo: titolo,
      artista: artista,
      artistaId: artistaId,
      tipo: 'single',
      data: data,
      link: 'https://www.deezer.com/album/$id',
      spotify: 'https://open.spotify.com/search/x',
      notificata: when,
    );

NewsItem annuncio(String id, String titolo, String data) => NewsItem(
      id: id,
      titolo: titolo,
      artista: 'ENHYPEN',
      artistaId: '7',
      tipo: 'album',
      data: data,
      link: 'https://music.apple.com/it/album/$id',
    );

/// The widgets of the home screen, in memory.
class FakeBridge implements WidgetBridge {
  final saved = <String, String?>{};
  int refreshes = 0;
  final _links = StreamController<Uri?>.broadcast();

  @override
  Future<void> save(Map<String, String?> data) async => saved.addAll(data);

  @override
  Future<void> refresh() async => refreshes++;

  @override
  Future<Uri?> initialLink() async => null;

  @override
  Stream<Uri?> get links => _links.stream;
}

void main() {
  group('i testi', () {
    test('quanto manca a un’uscita annunciata', () {
      final today = DateTime(2026, 11, 15, 16);
      expect(daysLeftLabel('2026-11-15', today), 'esce oggi');
      expect(daysLeftLabel('2026-11-16', today), 'esce domani');
      expect(daysLeftLabel('2026-11-20', today), 'esce il 20/11/2026 (tra 5 giorni)');
      expect(daysLeftLabel('2027-04-01', today), 'esce il 01/04/2027 (tra 137 giorni)'); // across the time change
    });

    test('il widget "Ultime uscite": le ultime tre', () {
      final when = DateTime(2026, 11, 15);
      expect(novitaText(const []), 'Nessuna novità per ora.');
      expect(
        novitaText([for (var i = 1; i <= 5; i++) novita('$i', 'Canzone $i', 'Ava Max', '1', when)]),
        '• Canzone 1 — Ava Max\n• Canzone 2 — Ava Max\n• Canzone 3 — Ava Max',
      );
    });

    test('il widget "Prossimo da recuperare": l’artista ascoltato per ultimo, e la sua prossima uscita', () {
      const a = SavedArtist(id: '1', nome: 'Alfa', lista: Lists.recuperando, data: {
        'fatte': {'single|x': {'s': 'a', 't': 5}},
      });
      const b = SavedArtist(id: '2', nome: 'Beta', lista: Lists.recuperando, data: {
        'fatte': {'single|y': {'s': 'a', 't': 9}},
      });
      const c = SavedArtist(id: '3', nome: 'Gamma', lista: Lists.recuperando);
      expect(currentArtist([a, b, c])!.id, '2');
      expect(currentArtist([c])!.id, '3');
      expect(currentArtist(const []), isNull);
      final entry = DiscoEntry()
        ..state = LoadState.ok
        ..releases = [release('Y', '2020-01-01'), release('Z', '2021-01-01')];
      expect(nextText(b, entry), (titolo: 'Z', dettaglio: 'Beta · Singolo · 1 di 2', id: '2'));
      expect(nextText(null, null).titolo, 'Niente da recuperare');
      expect(nextText(c, DiscoEntry()).dettaglio, 'Apri CNS per caricare la discografia.');
    });
  });

  group('la pagina Novità', () {
    Future<TestApp> open(WidgetTester tester, {void Function(TestApp app)? before}) async {
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

    testWidgets('le nuove contate nel menu finché non apri la pagina', (tester) async {
      final app = await open(tester, before: (app) {
        app.seen.value = DateTime(2026, 11, 15, 12).millisecondsSinceEpoch; // opened at noon
        app.newsBackend.novita['capo'] = [
          novita('1', 'Nuova', 'Ava Max', '4050205', DateTime(2026, 11, 15, 15)),
          novita('2', 'Vecchia', 'Ava Max', '4050205', DateTime(2026, 11, 14, 9)),
        ];
      });
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('1')), findsOneWidget);
      await tester.tap(menu('Novità'));
      await tester.pumpAndSettle();
      expect(find.text('Nuova'), findsOneWidget);
      expect(find.text('Vecchia'), findsOneWidget);
      expect(find.text('notificata il 15/11/2026 alle 15:00'), findsOneWidget);
      expect(app.news.unseen, 0);
      expect(app.seen.value, app.clock.millisecondsSinceEpoch);
      expect(tester.takeException(), isNull);
    });

    testWidgets('In arrivo in cima: oggi con Spotify, poi le prossime; le passate no', (tester) async {
      await open(tester, before: (app) {
        app.newsBackend.anteprime['capo'] = [
          annuncio('a', 'Fra cinque giorni', '2026-11-20'),
          annuncio('b', 'Oggi', '2026-11-15'),
          annuncio('c', 'Ieri', '2026-11-14'),
        ];
      });
      await tester.tap(menu('Novità'));
      await tester.pumpAndSettle();
      expect(find.text('In arrivo'), findsOneWidget);
      expect(find.text('Ieri'), findsNothing);
      final titles = tester
          .widgetList<Text>(find.byWidgetPredicate((w) => w is Text && (w.data == 'Oggi' || w.data == 'Fra cinque giorni')))
          .map((t) => t.data)
          .toList();
      expect(titles, ['Oggi', 'Fra cinque giorni']);
      expect(find.text('esce oggi'), findsOneWidget);
      expect(find.text('esce il 20/11/2026 (tra 5 giorni)'), findsOneWidget);
      expect(find.text('Spotify'), findsOneWidget); // solo quella di oggi
      expect(find.text('Apple Music'), findsNWidgets(2));
      expect(find.text('Nessuna novità per ora.'), findsOneWidget);
    });

    testWidgets('togli una Novità scorrendo, o svuotale tutte con conferma', (tester) async {
      final app = await open(tester, before: (app) {
        app.newsBackend.novita['capo'] = [
          novita('1', 'Prima', 'Ava Max', '4050205', DateTime(2026, 11, 15, 15)),
          novita('2', 'Seconda', 'Ava Max', '4050205', DateTime(2026, 11, 15, 14)),
          novita('3', 'Terza', 'Ava Max', '4050205', DateTime(2026, 11, 15, 13)),
        ];
      });
      await tester.tap(menu('Novità'));
      await tester.pumpAndSettle();
      await tester.drag(find.text('Prima'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(app.newsBackend.novita['capo']!.map((n) => n.id), ['2', '3']);
      await tester.tap(find.text('Svuota le Novità'));
      await tester.pumpAndSettle();
      expect(find.text('Svuotare le Novità?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Svuota'));
      await tester.pumpAndSettle();
      expect(app.newsBackend.novita['capo'], isEmpty);
      expect(find.text('Nessuna novità per ora.'), findsOneWidget);
    });

    testWidgets("In arrivo anche nella pagina dell'artista", (tester) async {
      await open(tester, before: (app) {
        app.artistsBackend.put('capo', '7', {'nome': 'ENHYPEN', 'lista': Lists.controllare, 'nota': ''});
        app.newsBackend.anteprime['capo'] = [annuncio('a', 'ROMANCE : UNTOLD', '2026-11-20')];
      });
      await tester.tap(find.text('ENHYPEN'));
      await tester.pumpAndSettle();
      expect(find.text('In arrivo'), findsOneWidget);
      expect(find.text('ROMANCE : UNTOLD'), findsOneWidget);
    });

    testWidgets('il tocco su un widget apre la pagina giusta', (tester) async {
      await open(tester, before: (app) {
        app.artistsBackend.put('capo', '7', {'nome': 'ENHYPEN', 'lista': Lists.recuperando, 'nota': ''});
      });
      widgetLink.value = Uri.parse('cns://novita');
      await tester.pumpAndSettle();
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, novitaIndex);
      widgetLink.value = Uri.parse('cns://artista/7');
      await tester.pumpAndSettle();
      expect(find.text('Segnalibro'), findsOneWidget); // la pagina di ENHYPEN, in Recuperando
      expect(widgetLink.value, isNull);
    });
  });

  testWidgets('i widget seguono le Novità e il segnalibro', (tester) async {
    final app = TestApp();
    app.artistsBackend.put('capo', '7', {
      'nome': 'ENHYPEN',
      'lista': Lists.recuperando,
      'nota': '',
      'fatte': {'single|given taken': {'s': 'a', 't': 1}},
    });
    app.deezer.discographies['7'] = [release('Given-Taken', '2020-11-30'), release('Drunk-Dazed', '2021-04-26')];
    app.newsBackend.novita['capo'] = [novita('1', 'Bite Me', 'ENHYPEN', '7', DateTime(2026, 11, 15))];
    final bridge = FakeBridge();
    final sync = WidgetSync(bridge, app.news, app.artists, app.discos);
    addTearDown(sync.dispose);
    await tester.pumpWidget(app.widget);
    await tester.tap(find.text('Accedi con Google'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(bridge.saved['novita_testo'], '• Bite Me — ENHYPEN');
    expect(bridge.saved['prossimo_titolo'], 'Drunk-Dazed');
    expect(bridge.saved['prossimo_dettaglio'], 'ENHYPEN · Singolo · 1 di 2');
    expect(bridge.saved['prossimo_id'], '7');
    expect(bridge.refreshes, greaterThan(0));
  });
}
