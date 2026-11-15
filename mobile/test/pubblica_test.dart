import 'dart:convert';
import 'dart:io';

import 'package:cns/data/updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'copia_test.dart' show settingsScroll;
import 'fakes.dart';

Map<String, dynamic> release(String tag, {bool draft = false, bool pre = false, bool apk = true}) => {
      'tag_name': tag,
      'draft': draft,
      'prerelease': pre,
      'html_url': 'https://github.com/StardustXYZ/CNS/releases/tag/$tag',
      'body': 'Novità della $tag',
      'assets': [
        if (apk) {'name': 'cns-$tag.apk', 'browser_download_url': 'https://github.com/x/$tag.apk'},
        {'name': 'note.txt', 'browser_download_url': 'https://github.com/x/note.txt'},
      ],
    };

void main() {
  group('gli aggiornamenti', () {
    test('confronto delle versioni', () {
      expect(compareVersions('1.10.0', '1.9.2'), 1);
      expect(compareVersions('1.0.0', '1.0.0+12'), 0);
      expect(compareVersions('0.9', '1.0.0'), -1);
    });

    test("l'ultima versione pubblicata, senza bozze, prove e release senza APK", () {
      final latest = latestRelease([
        release('app-v1.0.0'),
        release('app-v1.2.0', draft: true),
        release('app-v1.1.0', pre: true),
        release('app-v1.0.5', apk: false),
        release('v9.9.9'),
        release('app-v1.0.2'),
      ]);
      expect(latest!.version, '1.0.2');
      expect(latest.apkUrl, 'https://github.com/x/app-v1.0.2.apk');
      expect(latestRelease({'message': 'Not Found'}), isNull);
    });

    test('avviso per una versione nuova, che si chiude con «Non ora» fino alla prossima', () async {
      final dir = await Directory.systemTemp.createTemp('cns-agg');
      addTearDown(() => dir.delete(recursive: true));
      var releases = [release('app-v1.0.0'), release('app-v1.1.0')];
      final client = MockClient((req) async {
        expect(req.url.toString(), releasesUrl);
        return http.Response(jsonEncode(releases), 200);
      });
      final store = UpdateStore(currentVersion: '1.0.0', client: client, dismissedFile: () async => File('${dir.path}/x'));
      await store.check();
      expect(store.available!.version, '1.1.0');
      expect(store.showNotice, isTrue);
      await store.dismiss();
      expect(store.showNotice, isFalse);
      releases = [...releases, release('app-v1.2.0')];
      await store.check();
      expect(store.showNotice, isTrue); // even newer: it comes back
      final same = UpdateStore(currentVersion: '1.2.0', client: client, dismissedFile: () async => File('${dir.path}/y'));
      await same.check();
      expect(same.available, isNull);
    });

    test('GitHub non risponde: un messaggio, nessun avviso', () async {
      final store = UpdateStore(
        currentVersion: '1.0.0',
        client: MockClient((_) async => http.Response('', 503)),
        dismissedFile: () async => File('${Directory.systemTemp.path}/cns-non-esiste/x'),
      );
      await store.check();
      expect(store.available, isNull);
      expect(store.problem, 'Non riesco a controllare se ci sono versioni nuove.');
    });
  });

  group('Impostazioni', () {
    Future<TestApp> openSettings(WidgetTester tester) async {
      tester.view.physicalSize = const Size(375 * 3, 812 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final app = TestApp();
      await tester.pumpWidget(app.widget);
      await tester.tap(find.text('Accedi con Google'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Impostazioni')));
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('la pagina Privacy si apre dal riquadro App', (tester) async {
      await openSettings(tester);
      await tester.scrollUntilVisible(find.text('Privacy'), 300, scrollable: settingsScroll());
      await tester.tap(find.text('Privacy'));
      await tester.pumpAndSettle();
      expect(find.text('Cosa salva CNS'), findsOneWidget);
      expect(find.text('Cancellare i dati'), findsNothing); // further down
      await tester.scrollUntilVisible(find.text('Cancellare i dati'), 300);
      expect(find.text('Cancellare i dati'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets("«Elimina l'account» chiede conferma, poi riporta all'accesso", (tester) async {
      final app = await openSettings(tester);
      await tester.tap(find.text('Elimina l’account'));
      await tester.pumpAndSettle();
      expect(find.text('Eliminare l’account?'), findsOneWidget);
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(app.accountBackend.deleted, isEmpty);

      await tester.tap(find.text('Elimina l’account'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Elimina'));
      await tester.pumpAndSettle();
      expect(app.accountBackend.deleted, ['capo']);
      expect(find.text('Accedi con Google'), findsOneWidget);
      expect(find.text('Account eliminato.'), findsOneWidget);
    });
  });
}
