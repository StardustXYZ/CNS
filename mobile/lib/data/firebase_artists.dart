import 'package:cloud_firestore/cloud_firestore.dart';

import 'artists.dart';
import 'deezer.dart';

/// The artists in Firestore, utenti/{uid}/artisti/{deezerId}: the same documents and fields
/// as the web app (web/firebase.js), checked by the rules (validArtist).
class FirebaseArtistsBackend implements ArtistsBackend {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _artists(String uid) => _db.collection('utenti/$uid/artisti');

  @override
  Stream<List<SavedArtist>> watch(String uid) =>
      _artists(uid).snapshots().map((snap) => [for (final d in snap.docs) SavedArtist.fromMap(d.id, d.data())]);

  @override
  Future<void> add(String uid, List<DeezerArtist> artists, String lista) async {
    // A batch holds at most 500 writes: the import goes in pieces
    for (var start = 0; start < artists.length; start += 400) {
      final batch = _db.batch();
      for (final a in artists.skip(start).take(400)) {
        batch.set(_artists(uid).doc(a.id), {
          'nome': a.name.length > 200 ? a.name.substring(0, 200) : a.name,
          'foto': a.picture,
          'link': a.link,
          'fan': a.fans,
          'lista': lista,
          'nota': '',
          'aggiunto': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  @override
  Future<void> move(String uid, String id, String lista) => _artists(uid).doc(id).update({'lista': lista});

  @override
  Future<void> remove(String uid, String id) => _artists(uid).doc(id).delete();
}
