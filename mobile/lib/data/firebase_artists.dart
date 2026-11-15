import 'package:cloud_firestore/cloud_firestore.dart';

import 'artists.dart';
import 'deezer.dart';

/// The artists in Firestore, utenti/{uid}/artisti/{deezerId}: the same documents and fields
/// as the web app (web/firebase.js), checked by the rules (validArtist).
class FirebaseArtistsBackend implements ArtistsBackend {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _artists(String uid) => _db.collection('utenti/$uid/artisti');

  @override
  Stream<List<SavedArtist>> watch(String uid) => _artists(uid)
      .snapshots()
      .map((snap) => [for (final d in snap.docs) SavedArtist.fromMap(d.id, _dates(d.data()) as Map<String, dynamic>)]);

  /// Firestore's dates (Timestamp, e.g. "aggiunto") as DateTime: the rest of the app (and the
  /// backup file) does not need to know about Firestore.
  static Object? _dates(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is Map) return <String, dynamic>{for (final e in value.entries) '${e.key}': _dates(e.value)};
    if (value is List) return [for (final v in value) _dates(v)];
    return value;
  }

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
  Future<void> update(String uid, String id, Map<String, dynamic> fields) => _artists(uid).doc(id).update(fields);

  @override
  Future<void> remove(String uid, String id) => _artists(uid).doc(id).delete();
}
