import 'package:cloud_firestore/cloud_firestore.dart';

import 'news.dart';

/// Novità and In arrivo in Firestore, written only by GitHub; the account reads them and can
/// delete the Novità (the rules allow nothing else), as the web app (web/firebase.js).
class FirebaseNewsBackend implements NewsBackend {
  final _db = FirebaseFirestore.instance;

  static const _shown = 200; // the most recent ones are enough for the page

  static DateTime? _time(Object? value) => value is Timestamp ? value.toDate() : null;

  @override
  Stream<List<NewsItem>> watchNovita(String uid) => _db
      .collection('utenti/$uid/novita')
      .orderBy('notificata', descending: true)
      .limit(_shown)
      .snapshots()
      .map((snap) => [
            for (final d in snap.docs) NewsItem.fromMap(d.id, d.data(), notificata: _time(d.data()['notificata'])),
          ]);

  @override
  Stream<List<NewsItem>> watchAnteprime(String uid) => _db
      .collection('utenti/$uid/anteprime')
      .snapshots()
      .map((snap) => [for (final d in snap.docs) NewsItem.fromMap(d.id, d.data())]);

  @override
  Future<void> removeNovita(String uid, List<String> ids) async {
    for (var start = 0; start < ids.length; start += 400) {
      final batch = _db.batch();
      for (final id in ids.skip(start).take(400)) {
        batch.delete(_db.doc('utenti/$uid/novita/$id'));
      }
      await batch.commit();
    }
  }
}
