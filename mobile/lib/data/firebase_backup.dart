import 'package:cloud_firestore/cloud_firestore.dart';

import 'backup.dart';

/// The backup in Firestore: utenti/{uid} for the settings, utenti/{uid}/artisti for the
/// artists, as the web app (web/firebase.js: restoreArtists, saveSettings).
class FirebaseBackupBackend implements BackupBackend {
  final _db = FirebaseFirestore.instance;

  @override
  Future<Map<String, dynamic>> readSettings(String uid) async =>
      (await _db.doc('utenti/$uid').get()).data() ?? <String, dynamic>{};

  @override
  Future<void> restoreArtists(String uid, List<(String, Map<String, dynamic>)> artists) async {
    // Firestore takes up to 500 writes at once
    for (var start = 0; start < artists.length; start += 400) {
      final batch = _db.batch();
      for (final (id, fields) in artists.skip(start).take(400)) {
        batch.set(_db.doc('utenti/$uid/artisti/$id'), fields);
      }
      await batch.commit();
    }
  }

  @override
  Future<void> saveSettings(String uid, Map<String, dynamic> fields) =>
      _db.doc('utenti/$uid').set(fields, SetOptions(merge: true));
}
