import 'dart:convert';

import 'package:cns/data/deezer.dart';
import 'package:cns/data/importer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fakes.dart';

http.Response json(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});

void main() {
  group('i testi', () {
    test('normalize: accenti, maiuscole e punteggiatura non contano', () {
      expect(normalize('Beyoncé'), 'beyonce');
      expect(normalize('  K/DA  '), 'k da');
      expect(normalize('Måneskin'), 'maneskin');
      expect(normalize('AC/DC'), normalize('ac dc'));
    });

    test('i codici nei link di Deezer', () {
      expect(artistIdFromLink('https://www.deezer.com/it/artist/12948083?app_id=1'), '12948083');
      expect(artistIdFromLink('https://www.deezer.com/artist/27'), '27');
      expect(artistIdFromLink('Daft Punk'), isNull);
      expect(profileIdFromLink('https://www.deezer.com/it/profile/2529'), '2529');
      expect(profileIdFromLink('https://www.deezer.com/en-gb/profile/5?utm_source=x'), '5');
      expect(profileIdFromLink('https://www.deezer.com/it/artist/27'), isNull);
      expect(isShortLink('https://link.deezer.com/s/30Z5Ig0'), isTrue);
      expect(isShortLink('https://www.deezer.com/it/profile/5'), isFalse);
    });

    test('i fan come nel web', () {
      expect(fansLabel(1), '1 fan');
      expect(fansLabel(136074), '136.074 fan');
      expect(fansLabel(1200000), '1,2 mln di fan');
      expect(fansLabel(4000000), '4 mln di fan');
    });

    test("prima il nome esatto con più fan: Amy Lee è quinta su Deezer", () {
      final results = [
        deezerArtist('1', 'Amy Leeds', fans: 10),
        deezerArtist('2', 'Amy Lee & Friends', fans: 5),
        deezerArtist('3', 'Amy lee', fans: 20),
        deezerArtist('15741', 'Amy Lee', fans: 300000),
      ];
      expect(rankArtists('amy lee', results).map((a) => a.id).toList(), ['15741', '3', '1', '2']);
      expect(isExactMatch('Amy Lee', results.last), isTrue);
      expect(isExactMatch('Amy Lee', results.first), isFalse);
    });
  });

  group('il client di Deezer (con risposte finte)', () {
    test('la ricerca legge gli artisti e li ordina', () async {
      final client = DeezerClient(MockClient((req) async {
        expect(req.url.path, '/search/artist');
        expect(req.url.queryParameters['q'], 'Amy Lee');
        return json({
          'data': [
            {'id': 1, 'name': 'Amy Leeds', 'nb_fan': 10, 'picture_big': 'p1'},
            {'id': 15741, 'name': 'Amy Lee', 'nb_fan': 300000, 'nb_album': 40, 'link': 'https://www.deezer.com/artist/15741'},
          ],
        });
      }));
      final found = await client.searchArtists('Amy Lee');
      expect(found.first.id, '15741');
      expect(found.first.albums, 40);
      expect(found.last.picture, 'p1');
      expect(found.last.link, 'https://www.deezer.com/artist/1');
    });

    test('troppe richieste (codice 4): aspetta e riprova', () async {
      var calls = 0;
      final client = DeezerClient(MockClient((req) async {
        calls++;
        return calls == 1
            ? json({'error': {'type': 'Exception', 'message': 'Quota limit exceeded', 'code': 4}})
            : json({'id': 27, 'name': 'Daft Punk'});
      }));
      expect((await client.artist('27')).name, 'Daft Punk');
      expect(calls, 2);
    });

    test('"no data" diventa "Non trovato su Deezer."', () async {
      final client = DeezerClient(MockClient((req) async => json({'error': {'message': 'no data', 'code': 800}})));
      expect(() => client.artist('0'), throwsA(isA<DeezerError>().having((e) => e.message, 'm', 'Non trovato su Deezer.')));
    });

    test('gli artisti di un profilo: tutte le pagine', () async {
      final pages = <String>[];
      final client = DeezerClient(MockClient((req) async {
        pages.add(req.url.queryParameters['index']!);
        final index = int.parse(req.url.queryParameters['index']!);
        return index == 0
            ? json({
                'data': [for (var i = 0; i < 100; i++) {'id': i, 'name': 'A$i'}],
                'next': 'https://api.deezer.com/user/5/artists?index=100',
              })
            : json({
                'data': [{'id': 100, 'name': 'Ultimo'}],
              });
      }));
      final found = await client.profileArtists('5');
      expect(found.length, 101);
      expect(found.last.name, 'Ultimo');
      expect(pages, ['0', '100']);
    });
  });

  group("l'importazione", () {
    test("l'elenco: un nome per riga, senza puntini, numeri e doppioni", () {
      expect(parseNames('- Ava Max\n2. Arctic Monkeys\n\n• K/DA\nava max\nTyler, The Creator\r\n'),
          ['Ava Max', 'Arctic Monkeys', 'K/DA', 'Tyler, The Creator']);
    });

    test('i nomi cercati su Deezer: esatti con la spunta, diversi senza, mancanti a parte', () async {
      final deezer = FakeDeezer();
      final progress = <int>[];
      final found = await findByNames(deezer, ['Amy Lee', 'Daft', 'Nessuno Così'],
          pause: Duration.zero, onProgress: (done, _) => progress.add(done));
      expect(found[0].artist!.id, '15741'); // il nome esatto, non "Amy Leeds"
      expect(found[0].selected, isTrue);
      expect(found[1].artist!.name, 'Daft Punk');
      expect(found[1].exact, isFalse);
      expect(found[1].selected, isFalse);
      expect(found[2].artist, isNull);
      expect(progress, [1, 2, 3]);
    });

    test('il profilo: dal link, dal numero, anche dal link breve; privato: messaggio chiaro', () async {
      final deezer = FakeDeezer()..profiles['2529'] = [deezerArtist('27', 'Daft Punk'), deezerArtist('13', 'Eminem')];
      expect((await findFromProfile(deezer, 'https://www.deezer.com/it/profile/2529')).length, 2);
      expect((await findFromProfile(deezer, '2529')).first.selected, isTrue);
      expect((await findFromProfile(deezer, 'https://link.deezer.com/s/abc')).length, 2);
      expect(() => findFromProfile(deezer, 'https://www.deezer.com/it/profile/1'),
          throwsA(isA<DeezerError>().having((e) => e.message, 'm', contains('privato'))));
      expect(() => findFromProfile(deezer, 'ciao'), throwsA(isA<DeezerError>()));
    });
  });
}
