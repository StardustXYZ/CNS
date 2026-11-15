import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'notifications.dart';

/// Firebase Cloud Messaging. The notifications sent by GitHub carry their title and text:
/// Android shows them by itself when the app is closed; with the app open they arrive here.
class FirebasePushBackend implements PushBackend {
  final _messaging = FirebaseMessaging.instance;

  static bool _allowed(NotificationSettings s) =>
      s.authorizationStatus == AuthorizationStatus.authorized || s.authorizationStatus == AuthorizationStatus.provisional;

  static Uri? _link(RemoteMessage? m) {
    final link = m?.data['link'];
    return link is String ? Uri.tryParse(link) : null;
  }

  @override
  Future<bool> requestPermission() async => _allowed(await _messaging.requestPermission());

  @override
  Future<bool> hasPermission() async => _allowed(await _messaging.getNotificationSettings());

  // The classic messaging token: it is what app/services/fcm.py sends to (messages:send with
  // "token"), as in CNV.
  @override
  // ignore: deprecated_member_use
  Future<String?> token() => _messaging.getToken();

  @override
  // ignore: deprecated_member_use
  Stream<String> tokenRefresh() => _messaging.onTokenRefresh;

  @override
  Stream<String> foreground() => FirebaseMessaging.onMessage
      .map((m) => [m.notification?.title, m.notification?.body].whereType<String>().join('\n'))
      .where((text) => text.isNotEmpty);

  @override
  Future<Uri?> initialLink() async => _link(await _messaging.getInitialMessage());

  @override
  Stream<Uri> openedLinks() => FirebaseMessaging.onMessageOpenedApp.map(_link).where((u) => u != null).cast<Uri>();
}

/// The phones in Firestore: utenti/{uid}/telefoni/{phone} = {token, aggiornato} (validPhone).
class FirebasePhonesBackend implements PhonesBackend {
  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid, String phone) => _db.doc('utenti/$uid/telefoni/$phone');

  @override
  Future<bool> hasPhone(String uid, String phone) async =>
      (await _doc(uid, phone).get(const GetOptions(source: Source.server))).exists;

  @override
  Future<void> savePhone(String uid, String phone, String token) =>
      _doc(uid, phone).set({'token': token, 'aggiornato': FieldValue.serverTimestamp()});

  @override
  Future<void> removePhone(String uid, String phone) => _doc(uid, phone).delete();
}
