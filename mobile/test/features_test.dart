import 'package:cns/data/artists.dart';
import 'package:cns/data/discografia.dart';
import 'package:cns/data/segnalibro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late Release arcane, warriors, rise;

  Future<TestApp> open(WidgetTester tester, {String lista = Lists.recuperando, Map<String, dynamic> extra = const {}}) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = TestApp();
    warriors = release('Warriors', '2014-09-19');
    rise = release('RISE', '2018-09-24');
    arcane = release('Arcane League of Legends', '2021-11-20', 'album');
    app.artistsBackend.put('capo', '80', {'nome': 'League of Legends', 'lista': lista, 'nota': '', ...extra});
    app.deezer.discographies['80'] = [warriors, rise, arcane];
    app.deezer.trackLists[arcane.id] = const [
      Track(id: '1', title: 'Enemy', position: 1, duration: 173),
      Track(id: '2', title: 'Playground', position: 2, duration: 236),
      Track(id: '3', title: 'Paint The Town Blue', position: 1, disk: 2, duration: 190),
    ];
    app.deezer.similar['80'] = [deezerArtist('27', 'Daft Punk', fans: 4000000), deezerArtist('13', 'Eminem')];
    app.artistsBackend.put('capo', '13', {'nome': 'Eminem', 'lista': Lists.controllare, 'nota': ''});
    await tester.pumpWidget(app.widget);
    await tester.tap(find.text('Accedi con Google'));
    await tester.pumpAndSettle();
    if (lista == Lists.recuperando) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Recuperando')));
      await tester.pumpAndSettle();
    }
    return app;
  }

  Future<void> openArtist(WidgetTester tester) async {
    await tester.tap(find.text('League of Legends'));
    await tester.pumpAndSettle();
  }

  Finder pageScroll() => find.byType(Scrollable).first;

  testWidgets("la lista delle canzoni: dischi, durate, e le spunte che segnano l'album", (tester) async {
    final app = await open(tester);
    await openArtist(tester);
    await tester.scrollUntilVisible(find.text('Arcane League of Legends'), 300, scrollable: pageScroll());
    await tester.tap(find.text('Arcane League of Legends'));
    await tester.pumpAndSettle();
    expect(find.text('3 canzoni · 10 min · ascoltate 0'), findsOneWidget);
    expect(find.text('Disco 2'), findsOneWidget);
    expect(find.text('2:53'), findsOneWidget);

    for (final song in ['Paint The Town Blue', 'Enemy', 'Playground']) {
      await tester.tap(find.text(song));
      await tester.pumpAndSettle();
    }
    final saved = app.artistsBackend.saved('capo', '80')!;
    expect(saved.canzoni['album|arcane league of legends']!.keys.toSet(), {'enemy', 'playground', 'paint the town blue'});
    expect(saved.fatte['album|arcane league of legends']!.state, listened); // tutte spuntate: ascoltato
    expect(find.text('3 canzoni · 10 min · ascoltate 3'), findsOneWidget);

    await tester.tap(find.text('Enemy'));
    await tester.pumpAndSettle();
    expect(app.artistsBackend.saved('capo', '80')!.fatte.containsKey('album|arcane league of legends'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fuori da Recuperando la lista delle canzoni è senza spunte', (tester) async {
    await open(tester, lista: Lists.controllare);
    await openArtist(tester);
    await tester.scrollUntilVisible(find.text('Arcane League of Legends'), 300, scrollable: pageScroll());
    await tester.tap(find.text('Arcane League of Legends'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('3 canzoni · 10 min'), findsOneWidget);
  });

  testWidgets("ordine libero: «✓ Ascoltato» su un'uscita qualsiasi, senza toccare le precedenti", (tester) async {
    final app = await open(tester);
    await openArtist(tester);
    await tester.scrollUntilVisible(find.text('Arcane League of Legends'), 300, scrollable: pageScroll());
    await tester.ensureVisible(find.text('✓ Ascoltato').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('✓ Ascoltato').last); // l'album, l'ultima della coda
    await tester.pumpAndSettle();
    expect(app.artistsBackend.saved('capo', '80')!.fatte.keys, ['album|arcane league of legends']);
  });

  testWidgets('«Ti potrebbero piacere»: senza chi è già salvato, con il + per aggiungere', (tester) async {
    final app = await open(tester);
    await openArtist(tester);
    await tester.scrollUntilVisible(find.text('Ti potrebbero piacere'), 300, scrollable: pageScroll());
    expect(find.text('Daft Punk'), findsOneWidget);
    expect(find.text('Eminem'), findsNothing); // già in Controllare
    await tester.tap(find.byTooltip('Aggiungi Daft Punk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aggiungi a Recuperando'));
    await tester.pumpAndSettle();
    expect(app.artistsBackend.saved('capo', '27')!.lista, Lists.recuperando);
    expect(find.text('Daft Punk aggiunto a Recuperando.'), findsOneWidget);
  });

  testWidgets('«Cosa ascolto adesso?»: una a caso, Ascoltato, Un’altra, solo album', (tester) async {
    final app = await open(tester);
    await tester.tap(find.text('Cosa ascolto adesso?'));
    await tester.pumpAndSettle();
    expect(find.text('Scelta tra 3 uscite da ascoltare.'), findsOneWidget);

    await tester.tap(find.text('Solo album ed EP'));
    await tester.pumpAndSettle();
    expect(find.text('Arcane League of Legends'), findsOneWidget);
    expect(find.text('Scelta tra 1 uscita da ascoltare.'), findsOneWidget);
    await tester.tap(find.text('Ascoltato'));
    await tester.pumpAndSettle();
    expect(app.artistsBackend.saved('capo', '80')!.fatte['album|arcane league of legends']!.state, listened);
    expect(find.text('Hai ascoltato tutto quello che c’è da recuperare 🎉'), findsOneWidget);

    await tester.tap(find.text('Solo album ed EP'));
    await tester.pumpAndSettle();
    final first = find.text('Warriors').evaluate().isNotEmpty ? 'Warriors' : 'RISE';
    await tester.tap(find.text('Un’altra'));
    await tester.pumpAndSettle();
    expect(find.text(first == 'Warriors' ? 'RISE' : 'Warriors'), findsOneWidget); // non la stessa di prima
  });
}
