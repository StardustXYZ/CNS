import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cns/data/artists.dart';
import 'package:cns/data/backup.dart';
import 'package:cns/data/copia.dart';
import 'package:cns/pages/impostazioni_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// The phone's files in memory.
class FakeFiles implements BackupFiles {
  String? savedName;
  String? savedText;
  String? toPick;
  bool cancel = false;

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    if (cancel) return false;
    savedName = fileName;
    savedText = utf8.decode(bytes);
    return true;
  }

  @override
  Future<String?> pick() async => cancel ? null : toPick;
}

void main() {
  final now = DateTime.utc(2026, 11, 15, 16);

  group('il formato, uguale a web/copia.js', () {
    test('un file fatto dall’app web si legge qui (tests/fixtures/copia_web.json)', () {
      final backup = parseBackup(File('../tests/fixtures/copia_web.json').readAsStringSync());
      expect(backup.artists.map((a) => a.$1), ['4050205', '7402526', '13']);
      expect(backup.ntfy, 'cns-prova-123');
      expect(backup.skipped, 0);
      expect(backup.saved, '2026-11-15T16:00:00.000Z');
      final (_, lol) = backup.artists[1];
      expect(fatteFromJsonCount(lol['fatte']), 2);
      expect(lol['canzoni'], {
        'album|arcane league of legends': {'enemy': 1763000000002},
      });
      expect(lol['auto_sposta'], true);
      expect(backup.artists[0].$2.containsKey('aggiunto'), isFalse); // Firebase sets its own
    });

    test('la copia fatta qui ha gli stessi campi di quella del web', () {
      final web = jsonDecode(File('../tests/fixtures/copia_web.json').readAsStringSync()) as Map<String, dynamic>;
      final mine = buildBackup(
        artists: [
          {
            'id': '4050205',
            'nome': 'Ava Max',
            'lista': 'controllare',
            'nota': 'aspetto il nuovo album',
            'foto': 'https://cdn/ava.jpg',
            'fan': 1235611,
            'link': 'https://www.deezer.com/artist/4050205',
            'tipi_avviso': ['album', 'single'],
            'aggiunto': DateTime.utc(2026, 11, 12, 19),
          },
        ],
        settings: {'ntfy': 'cns-prova-123', 'email': 'amico@example.com'},
        email: 'amico@example.com',
        now: now,
      );
      expect(mine.keys, web.keys);
      expect(mine['salvata'], web['salvata']);
      expect(mine['impostazioni'], web['impostazioni']);
      expect((mine['artisti'] as List).first, (web['artisti'] as List).first); // date as ISO text, as the web
      expect(backupFileName(DateTime(2026, 11, 3)), 'cns-copia-2026-11-03.json');
    });

    test('gli artisti non validi vengono saltati, gli altri restano', () {
      final text = jsonEncode({
        'formato': backupFormat,
        'versione': 1,
        'artisti': [
          {'id': '12948083', 'nome': 'Ava Max', 'lista': 'controllare'},
          {'id': 'abc', 'nome': 'Codice sbagliato', 'lista': 'controllare'},
          {'id': '1', 'nome': '', 'lista': 'controllare'},
          {'id': '2', 'nome': 'Lista sbagliata', 'lista': 'boh'},
          {'id': '3', 'nome': 'Nota lunga', 'lista': 'archivio', 'nota': 'x' * 600},
        ],
      });
      final backup = parseBackup(text);
      expect(backup.artists.map((a) => a.$1), ['12948083', '3']);
      expect(backup.skipped, 3);
      expect((backup.artists[1].$2['nota'] as String).length, 500);
      expect(backup.ntfy, isNull);
    });

    test('file sbagliati: gli stessi messaggi del web', () {
      Matcher says(String text) => throwsA(isA<BackupError>().having((e) => e.message, 'message', contains(text)));
      expect(() => parseBackup('non json'), says('non è JSON'));
      expect(() => parseBackup(jsonEncode({'votes': {}})), says('non è una copia di CNS'));
      expect(() => parseBackup(jsonEncode({'formato': backupFormat, 'versione': 99, 'artisti': []})),
          says('versione più nuova'));
      final odd = parseBackup(jsonEncode({
        'formato': backupFormat,
        'versione': 1,
        'artisti': [],
        'impostazioni': {'ntfy': 'con spazi'},
      }));
      expect(odd.ntfy, isNull);
    });
  });

  group('Salva e Ripristina in Impostazioni', () {
    Future<(TestApp, FakeFiles)> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(375 * 3, 812 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final app = TestApp();
      app.artistsBackend.put('capo', '27', {
        'nome': 'Daft Punk',
        'lista': Lists.controllare,
        'nota': 'casco',
        'aggiunto': DateTime.utc(2026, 11, 1),
      });
      app.backupBackend.settings['capo'] = {'ntfy': 'mio-argomento', 'email': 'capo@gmail.com'};
      await tester.pumpWidget(app.widget);
      await tester.tap(find.text('Accedi con Google'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Impostazioni')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Salva la copia'), 300, scrollable: settingsScroll());
      await tester.pumpAndSettle();
      return (app, app.files);
    }

    testWidgets('«Salva la copia» scrive il file come il web', (tester) async {
      final (_, files) = await open(tester);
      await tester.tap(find.text('Salva la copia'));
      await tester.pumpAndSettle();
      expect(files.savedName, 'cns-copia-2026-11-15.json');
      final saved = parseBackup(files.savedText!);
      expect(saved.artists.single.$1, '27');
      expect(saved.artists.single.$2['nota'], 'casco');
      expect(saved.ntfy, 'mio-argomento');
      expect(jsonDecode(files.savedText!)['artisti'][0]['aggiunto'], '2026-11-01T00:00:00.000Z');
      expect(find.text('Copia salvata: 1 artisti ✓'), findsOneWidget);
    });

    testWidgets('«Ripristina» chiede conferma, poi riscrive artisti e argomento', (tester) async {
      final (app, files) = await open(tester);
      files.toPick = File('../tests/fixtures/copia_web.json').readAsStringSync();
      await tester.tap(find.text('Ripristina da una copia'));
      await tester.pumpAndSettle();
      expect(find.text('Ripristinare la copia?'), findsOneWidget);
      expect(find.textContaining('Ripristino 3 artisti dalla copia.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Ripristina'));
      await tester.pumpAndSettle();
      expect(app.backupBackend.restored.map((a) => a.$1), ['4050205', '7402526', '13']);
      expect(app.backupBackend.settings['capo']!['ntfy'], 'cns-prova-123');
      expect(app.artistsBackend.saved('capo', '7402526')!.fatte.length, 2);
      expect(find.text('Ripristinati 3 artisti ✓'), findsOneWidget);
    });

    testWidgets('un file sbagliato: messaggio chiaro e niente scritto', (tester) async {
      final (app, files) = await open(tester);
      files.toPick = '{"votes": {}}';
      await tester.tap(find.text('Ripristina da una copia'));
      await tester.pumpAndSettle();
      expect(find.text('Copia non ripristinata: il file non è una copia di CNS.'), findsOneWidget);
      expect(app.backupBackend.restored, isEmpty);
    });
  });
}

int fatteFromJsonCount(Object? value) => value is Map ? value.length : 0;

/// The scrolling list of the Impostazioni page.
Finder settingsScroll() => find.descendant(of: find.byType(ImpostazioniPage), matching: find.byType(Scrollable)).first;
