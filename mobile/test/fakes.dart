import 'dart:async';

import 'package:cns/data/account.dart';
import 'package:cns/data/artists.dart';
import 'package:cns/data/backup.dart';
import 'package:cns/data/deezer.dart';
import 'package:cns/data/discografia.dart';
import 'package:cns/data/discography_store.dart';
import 'package:cns/data/news.dart';
import 'package:cns/main.dart';

import 'copia_test.dart' show FakeFiles;
import 'fake_account.dart';

/// Firestore's artists in memory (the documents as maps), with the live updates of snapshots().
class FakeArtistsBackend implements ArtistsBackend {
  final docs = <String, Map<String, Map<String, dynamic>>>{}; // uid -> id -> document
  final _changes = StreamController<String>.broadcast();
  int writes = 0;

  List<SavedArtist> _list(String uid) => [for (final e in (docs[uid] ?? {}).entries) SavedArtist.fromMap(e.key, e.value)];

  /// The artist as the app reads it.
  SavedArtist? saved(String uid, String id) {
    final d = docs[uid]?[id];
    return d == null ? null : SavedArtist.fromMap(id, d);
  }

  void put(String uid, String id, Map<String, dynamic> doc) => (docs[uid] ??= {})[id] = doc;

  @override
  Stream<List<SavedArtist>> watch(String uid) async* {
    yield _list(uid);
    yield* _changes.stream.where((u) => u == uid).map(_list);
  }

  @override
  Future<void> add(String uid, List<DeezerArtist> artists, String lista) async {
    writes++;
    for (final a in artists) {
      put(uid, a.id, {'nome': a.name, 'lista': lista, 'foto': a.picture, 'fan': a.fans, 'link': a.link, 'nota': ''});
    }
    _changes.add(uid);
  }

  @override
  Future<void> move(String uid, String id, String lista) => update(uid, id, {'lista': lista});

  @override
  Future<void> update(String uid, String id, Map<String, dynamic> fields) async {
    writes++;
    docs[uid]![id] = {...docs[uid]![id]!, ...fields};
    _changes.add(uid);
  }

  @override
  Future<void> remove(String uid, String id) async {
    writes++;
    docs[uid]?.remove(id);
    _changes.add(uid);
  }
}

DeezerArtist deezerArtist(String id, String name, {int fans = 1000}) =>
    DeezerArtist(id: id, name: name, fans: fans, albums: 10, link: 'https://www.deezer.com/artist/$id');

int _release = 1000;
Release release(String title, String date, [String type = 'single']) =>
    Release.fromApi({'id': _release++, 'title': title, 'release_date': date, 'record_type': type});

/// Deezer with a few artists, their discographies and the public profiles you give it; no network.
class FakeDeezer implements DeezerApi {
  final catalogue = [
    deezerArtist('27', 'Daft Punk', fans: 4000000),
    deezerArtist('15741', 'Amy Lee', fans: 300000),
    deezerArtist('99', 'Amy Leeds', fans: 50),
    deezerArtist('13', 'Eminem', fans: 9000000),
    deezerArtist('4050205', 'Ava Max', fans: 2000000),
  ];
  final profiles = <String, List<DeezerArtist>>{};
  final discographies = <String, List<Release>>{};
  final trackLists = <String, List<Track>>{}; // release id -> songs
  final similar = <String, List<DeezerArtist>>{};
  final searches = <String>[];
  final discographyCalls = <String>[];
  bool down = false;

  @override
  Future<List<DeezerArtist>> searchArtists(String query, {int limit = 15}) async {
    searches.add(query);
    final q = normalize(query);
    return rankArtists(
        query, catalogue.where((a) => normalize(a.name).contains(q) || q.contains(normalize(a.name))).toList());
  }

  @override
  Future<DeezerArtist> artist(String id) async =>
      catalogue.firstWhere((a) => a.id == id, orElse: () => throw const DeezerError('Non trovato su Deezer.'));

  @override
  Future<List<DeezerArtist>> profileArtists(String profileId) async {
    final found = profiles[profileId];
    if (found == null) throw const DeezerError('Non trovato su Deezer.');
    return found;
  }

  @override
  Future<String> resolveLink(String link) async => 'https://www.deezer.com/it/profile/2529?utm=share';

  @override
  Future<List<Track>> tracks(String releaseId) async => trackLists[releaseId] ?? const [];

  @override
  Future<List<DeezerArtist>> related(String artistId) async => similar[artistId] ?? const [];

  @override
  Future<List<Release>> discography(String artistId) async {
    discographyCalls.add(artistId);
    if (down) throw const DeezerError('Deezer non raggiungibile: controlla la connessione.');
    return discographies[artistId] ?? const [];
  }
}

/// Novità and In arrivo in memory, with live updates.
class FakeNewsBackend implements NewsBackend {
  final novita = <String, List<NewsItem>>{};
  final anteprime = <String, List<NewsItem>>{};
  final _changes = StreamController<String>.broadcast();

  void publish(String uid) => _changes.add(uid);

  @override
  Stream<List<NewsItem>> watchNovita(String uid) async* {
    yield [...?novita[uid]];
    yield* _changes.stream.where((u) => u == uid).map((_) => [...?novita[uid]]);
  }

  @override
  Stream<List<NewsItem>> watchAnteprime(String uid) async* {
    yield [...?anteprime[uid]];
    yield* _changes.stream.where((u) => u == uid).map((_) => [...?anteprime[uid]]);
  }

  @override
  Future<void> removeNovita(String uid, List<String> ids) async {
    novita[uid]?.removeWhere((n) => ids.contains(n.id));
    _changes.add(uid);
  }
}

/// The settings and the restore in memory; the restored artists go into the fake artists.
class FakeBackupBackend implements BackupBackend {
  FakeBackupBackend(this.artists);

  final FakeArtistsBackend artists;
  final settings = <String, Map<String, dynamic>>{};
  final restored = <(String, Map<String, dynamic>)>[];

  @override
  Future<Map<String, dynamic>> readSettings(String uid) async => {...?settings[uid]};

  @override
  Future<void> restoreArtists(String uid, List<(String, Map<String, dynamic>)> list) async {
    restored.addAll(list);
    for (final (id, fields) in list) {
      artists.put(uid, id, fields);
    }
    artists._changes.add(uid);
  }

  @override
  Future<void> saveSettings(String uid, Map<String, dynamic> fields) async =>
      settings[uid] = {...?settings[uid], ...fields};
}

/// The whole app with fakes: account, artists, Deezer and the copy of the discographies.
class TestApp {
  TestApp() {
    account = AccountStore(accountBackend);
    artists = ArtistStore(account, artistsBackend);
    discos = DiscographyStore(deezer, cache, now: () => clock);
    news = NewsStore(account, newsBackend, seen, now: () => clock);
    backupBackend = FakeBackupBackend(artistsBackend);
    backup = BackupService(account, artists, news, backupBackend, files, now: () => clock);
  }

  final accountBackend = FakeBackend();
  final artistsBackend = FakeArtistsBackend();
  final deezer = FakeDeezer();
  final cache = MemoryDiscoCache();
  final newsBackend = FakeNewsBackend();
  final seen = MemorySeenStore();
  DateTime clock = DateTime(2026, 11, 15, 16);
  late final AccountStore account;
  late final ArtistStore artists;
  late final DiscographyStore discos;
  late final NewsStore news;
  late final FakeBackupBackend backupBackend;
  late final BackupService backup;
  final files = FakeFiles();

  CnsApp get widget => CnsApp(
        account: account,
        artists: artists,
        deezer: deezer,
        discographies: discos,
        news: news,
        backup: backup,
      );
}
