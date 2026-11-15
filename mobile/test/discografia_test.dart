import 'dart:convert';
import 'dart:io';

import 'package:cns/data/discografia.dart';
import 'package:cns/data/segnalibro.dart';
import 'package:flutter_test/flutter_test.dart';

int _next = 1;
Release rel(String title, String date, [String type = 'single']) =>
    Release.fromApi({'id': _next++, 'title': title, 'release_date': date, 'record_type': type});

void main() {
  group('la discografia (come web/test/discografia.test.mjs)', () {
    test("i remix e le versioni finiscono sotto l'originale", () {
      final groups = groupReleases([
        rel('Sweet but Psycho (Paul Morrell Remix)', '2018-08-15'),
        rel('Sweet but Psycho (Acoustic)', '2018-08-15'),
        rel('Sweet but Psycho', '2018-08-17'),
        rel('Sweet but Psycho (The Remixes)', '2019-03-04'),
        rel('So Am I', '2019-03-07'),
        rel('So Am I (feat. NCT 127)', '2019-07-03'),
      ], 'Ava Max');
      expect(groups.length, 2);
      final sweet = groups.firstWhere((g) => g.main.title == 'Sweet but Psycho');
      expect(sweet.date, '2018-08-17'); // la data dell'originale, non quella dell'acustica
      expect(sweet.versions.length, 3);
      expect(groups.firstWhere((g) => g.main.title == 'So Am I').versions.length, 1);
    });

    test('album e singolo con lo stesso nome restano separati; deluxe ed explicit/clean si uniscono', () {
      final groups = groupReleases([
        rel('Heaven & Hell', '2020-09-18', 'album'),
        rel('Heaven & Hell (Deluxe)', '2021-03-01', 'album'),
        rel('Heaven & Hell', '2020-09-18', 'album'),
        rel('Heaven & Hell', '2020-08-01', 'single'),
      ], 'Ava Max');
      expect(groups.length, 2);
      expect(groups.firstWhere((g) => g.kind == 'album').versions.length, 2);
    });

    test('un EP e la sua versione deluxe album sono la stessa uscita', () {
      final groups = groupReleases([
        rel('Diamonds & Dancefloors (Deluxe)', '2023-05-01', 'album'),
        rel('Diamonds & Dancefloors', '2023-01-27', 'ep'),
      ], 'Ava Max');
      expect(groups.length, 1);
      expect(groups.single.kind, 'ep');
      expect(groups.single.main.title, 'Diamonds & Dancefloors');
    });

    test('conteggio per tipo e ordine per data', () {
      final groups = groupReleases([
        rel('Uno', '2018-04-20'),
        rel('Due', '2020-01-01', 'album'),
        rel('Tre', ''),
        rel('Quattro', '2026-11-06'),
        rel('BURN (feat. Ava Max)', '2026-10-09'),
      ], 'Ava Max');
      expect(countKinds(groups), {'single': 3, 'album': 1, 'featuring': 1});
      List<String> titles(List<ReleaseGroup> g) => g.map((x) => x.main.title).toList();
      expect(titles(arrange(groups)), ['Quattro', 'BURN (feat. Ava Max)', 'Due', 'Uno', 'Tre']);
      expect(titles(arrange(groups, oldestFirst: true)), ['Uno', 'Due', 'BURN (feat. Ava Max)', 'Quattro', 'Tre']);
      expect(titles(arrange(groups, kind: 'single', oldestFirst: true)), ['Uno', 'Quattro', 'Tre']);
    });

    test('date, link di Spotify e dati di Deezer', () {
      expect(dateLabel('2026-11-06'), '06/11/2026');
      expect(dateLabel(''), 'data sconosciuta');
      expect(spotifySearchUrl('K/DA', 'MORE'), 'https://open.spotify.com/search/K%2FDA%20MORE');
      final r = Release.fromApi({
        'id': 5,
        'title': 'X',
        'release_date': '0000-00-00',
        'record_type': 'EP',
        'cover_medium': 'c',
        'explicit_lyrics': true,
      });
      expect(r.toJson(),
          {'id': '5', 'title': 'X', 'type': 'ep', 'date': '', 'cover': 'c', 'link': 'https://www.deezer.com/album/5', 'explicit': true});
      expect(Release.fromJson(r.toJson()).toJson(), r.toJson()); // la copia sul telefono
    });
  });

  group('gli esempi condivisi con Python e JavaScript (tests/fixtures/doppioni.json)', () {
    final cases = jsonDecode(File('../tests/fixtures/doppioni.json').readAsStringSync()) as Map<String, dynamic>;

    test('titolo base', () {
      for (final c in cases['titolo_base'] as List) {
        expect(baseTitle(c[0] as String), c[1], reason: c[0] as String);
      }
    });

    test('featuring', () {
      for (final c in cases['featuring'] as List) {
        expect(isFeaturing(c[0] as String, c[1] as String), c[2], reason: '${c[0]} / ${c[1]}');
      }
    });

    test('chiave delle versioni', () {
      for (final c in cases['chiave'] as List) {
        final r = Release(id: '1', title: c[0] as String, type: c[1] as String);
        expect(groupKey(r, c[2] as String), c[3], reason: c[0] as String);
      }
    });
  });

  group('il segnalibro (come web/test/segnalibro.test.mjs)', () {
    final groups = groupReleases([
      rel('Warriors', '2014-09-19'),
      rel('Legends Never Die', '2017-09-21'),
      rel('Legends Never Die (Remix)', '2018-01-10'),
      rel('RISE', '2018-09-24'),
      rel('Take Over', '2020-09-23'),
      rel('Arcane League of Legends (Soundtrack from the Animated Series)', '2021-11-20', 'album'),
      rel('Worlds Collection', '2022-01-01', 'compile'),
      rel('GODS', '2023-10-03'),
    ], 'League of Legends');
    String keyOf(String title) => groups.firstWhere((g) => g.main.title == title).key;
    const arcane = 'Arcane League of Legends (Soundtrack from the Animated Series)';

    test('la coda va dalla più vecchia e lascia fuori le raccolte', () {
      final q = queueOf(groups);
      expect(q.all.map((g) => g.main.title), ['Warriors', 'Legends Never Die', 'RISE', 'Take Over', arcane, 'GODS']);
      expect(q.next!.main.title, 'Warriors');
      expect(q.total, 6);
      expect(q.finished, isFalse);
    });

    test('Ascoltato e Salta fanno avanzare il segnalibro', () {
      var fatte = mark({}, keyOf('Warriors'), listened, 1);
      fatte = mark(fatte, keyOf('Legends Never Die'), skipped, 2);
      final q = queueOf(groups, fatte);
      expect(q.next!.main.title, 'RISE');
      expect(q.listenedCount, 1);
      expect(q.skippedCount, 1);
      expect((q.done, q.total, q.percent), (2, 6, 33));
    });

    test('«Arrivato qui» segna tutto fino a quella uscita, senza cambiare le saltate', () {
      final start = mark({}, keyOf('Legends Never Die'), skipped, 1);
      final fatte = markUpTo(queueOf(groups).all, keyOf('Take Over'), start, 100);
      final q = queueOf(groups, fatte);
      expect(q.next!.main.title, arcane);
      expect(fatte[keyOf('Legends Never Die')]!.state, skipped);
      expect(fatte[keyOf('Take Over')]!.state, listened);
      expect(q.listenedCount, 3);
    });

    test("«Annulla» toglie l'ultimo segno, uno alla volta", () {
      var fatte = markUpTo(queueOf(groups).all, keyOf('RISE'), {}, 100);
      var (rest, key) = undoLast(fatte);
      expect(key, keyOf('RISE'));
      (rest, key) = undoLast(rest);
      expect(key, keyOf('Legends Never Die'));
      expect(queueOf(groups, rest).next!.main.title, 'Legends Never Die');
      expect(undoLast({}).$2, isNull);
      fatte = unmark(fatte, keyOf('Warriors'));
      expect(queueOf(groups, fatte).next!.main.title, 'Warriors');
    });

    test('fine della discografia e uscite nuove in fondo alla coda', () {
      final fatte = markUpTo(queueOf(groups).all, keyOf('GODS'), {}, 1);
      expect(queueOf(groups, fatte).finished, isTrue);
      final withNew = [...groups, ...groupReleases([rel('Ignite (2026)', '2026-11-13')], 'League of Legends')];
      final q = queueOf(withNew, fatte);
      expect(q.finished, isFalse);
      expect(q.next!.main.title, 'Ignite (2026)');
      expect(q.pending.length, 1);
    });

    test('i tipi scelti decidono cosa entra nella coda', () {
      expect(queueOf(groups, {}, ['album']).all.map((g) => g.main.title), [arcane]);
      expect(queueOf([], {}).finished, isFalse);
    });

    test('lo stesso formato del web in Firestore', () {
      final fatte = fatteFromJson({
        'single|rise': {'s': 'a', 't': 1700000000000},
        'single|gods': {'s': 's', 't': 5},
        'rotto': {'s': 'x', 't': 1},
        'anche': 'rotto',
      });
      expect(fatte.keys, ['single|rise', 'single|gods']);
      expect(fatteToJson(fatte), {
        'single|rise': {'s': 'a', 't': 1700000000000},
        'single|gods': {'s': 's', 't': 5},
      });
    });
  });

  group("l'ordine libero: una spunta per canzone", () {
    test('chiavi, durate e durata totale', () {
      final tracks = [
        const Track(id: '1', title: 'Intro', duration: 59),
        const Track(id: '2', title: 'Enemy (feat. JID)', duration: 225),
        const Track(id: '3', title: 'Intro', duration: 3725),
      ];
      expect(trackKeys(tracks), ['intro', 'enemy feat jid', 'intro#2']);
      expect(durationLabel(225), '3:45');
      expect(durationLabel(3725), '1:02:05');
      expect(totalLabel(2520), '42 min');
      expect(totalLabel(3900), '1 h 05 min');
      final t = Track.fromApi({'id': 9, 'title': 'X', 'track_position': 4, 'disk_number': 2, 'duration': 61});
      expect((t.position, t.disk, t.duration), (4, 2, 61));
    });

    test("l'ultima canzone spuntata segna l'uscita come ascoltata; togliendone una il segno sparisce", () {
      const songs = ['a', 'b'];
      var (canzoni, fatte) = toggleSong({}, {}, 'album|x', 'a', songs, 1);
      expect(canzoni, {'album|x': {'a': 1}});
      expect(fatte, isEmpty);
      (canzoni, fatte) = toggleSong(canzoni, fatte, 'album|x', 'b', songs, 2);
      expect(fatte['album|x']!.state, listened);
      (canzoni, fatte) = toggleSong(canzoni, fatte, 'album|x', 'a', songs, 3);
      expect(canzoni, {'album|x': {'b': 2}});
      expect(fatte, isEmpty);
      (canzoni, fatte) = toggleSong(canzoni, fatte, 'album|x', 'b', songs, 4);
      expect(canzoni, isEmpty); // nessuna spunta: l'uscita sparisce dalla mappa
      expect(canzoniToJson(canzoniFromJson({'album|y': {'s': 5, 'rotto': 'x'}, 'z': 3})), {'album|y': {'s': 5}});
    });

    test('una saltata resta saltata anche spuntando una canzone', () {
      final (_, fatte) = toggleSong({}, {'album|x': const Mark(skipped, 1)}, 'album|x', 'a', ['a', 'b'], 2);
      expect(fatte['album|x']!.state, skipped);
    });
  });
}
