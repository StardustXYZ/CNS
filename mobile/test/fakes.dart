import 'dart:async';

import 'package:cns/data/account.dart';
import 'package:cns/data/artists.dart';
import 'package:cns/data/deezer.dart';
import 'package:cns/data/discografia.dart';
import 'package:cns/data/discography_store.dart';
import 'package:cns/main.dart';

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
  Future<List<Release>> discography(String artistId) async {
    discographyCalls.add(artistId);
    if (down) throw const DeezerError('Deezer non raggiungibile: controlla la connessione.');
    return discographies[artistId] ?? const [];
  }
}

/// The whole app with fakes: account, artists, Deezer and the copy of the discographies.
class TestApp {
  TestApp() {
    account = AccountStore(accountBackend);
    artists = ArtistStore(account, artistsBackend);
    discos = DiscographyStore(deezer, cache, now: () => clock);
  }

  final accountBackend = FakeBackend();
  final artistsBackend = FakeArtistsBackend();
  final deezer = FakeDeezer();
  final cache = MemoryDiscoCache();
  DateTime clock = DateTime(2026, 11, 15, 16);
  late final AccountStore account;
  late final ArtistStore artists;
  late final DiscographyStore discos;

  CnsApp get widget => CnsApp(account: account, artists: artists, deezer: deezer, discographies: discos);
}
