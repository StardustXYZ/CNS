import 'dart:async';

import 'package:cns/data/account.dart';
import 'package:cns/data/artists.dart';
import 'package:cns/data/deezer.dart';
import 'package:cns/main.dart';

import 'fake_account.dart';

/// Firestore's artists in memory, with the live updates of snapshots().
class FakeArtistsBackend implements ArtistsBackend {
  final docs = <String, Map<String, SavedArtist>>{}; // uid -> id -> artist
  final _changes = StreamController<String>.broadcast();
  int writes = 0;

  List<SavedArtist> _list(String uid) => [...?docs[uid]?.values];

  @override
  Stream<List<SavedArtist>> watch(String uid) async* {
    yield _list(uid);
    yield* _changes.stream.where((u) => u == uid).map(_list);
  }

  @override
  Future<void> add(String uid, List<DeezerArtist> artists, String lista) async {
    writes++;
    for (final a in artists) {
      (docs[uid] ??= {})[a.id] = SavedArtist(id: a.id, nome: a.name, lista: lista, foto: a.picture, fan: a.fans);
    }
    _changes.add(uid);
  }

  @override
  Future<void> move(String uid, String id, String lista) async {
    writes++;
    final a = docs[uid]![id]!;
    docs[uid]![id] =
        SavedArtist(id: a.id, nome: a.nome, lista: lista, foto: a.foto, fan: a.fan, nota: a.nota, data: a.data);
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

/// Deezer with a few artists and the public profiles you give it; no network.
class FakeDeezer implements DeezerApi {
  final catalogue = [
    deezerArtist('27', 'Daft Punk', fans: 4000000),
    deezerArtist('15741', 'Amy Lee', fans: 300000),
    deezerArtist('99', 'Amy Leeds', fans: 50),
    deezerArtist('13', 'Eminem', fans: 9000000),
    deezerArtist('4050205', 'Ava Max', fans: 2000000),
  ];
  final profiles = <String, List<DeezerArtist>>{};
  final searches = <String>[];

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
}

/// The whole app with fakes: account, artists and Deezer.
class TestApp {
  TestApp() {
    account = AccountStore(accountBackend);
    artists = ArtistStore(account, artistsBackend);
  }

  final accountBackend = FakeBackend();
  final artistsBackend = FakeArtistsBackend();
  final deezer = FakeDeezer();
  late final AccountStore account;
  late final ArtistStore artists;

  CnsApp get widget => CnsApp(account: account, artists: artists, deezer: deezer);
}
