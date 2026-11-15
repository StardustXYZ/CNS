import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'account.dart';

/// Firebase Cloud Messaging behind an interface, so the tests can do without it.
abstract class PushBackend {
  Future<bool> requestPermission(); // asks Android (13+) the first time
  Future<bool> hasPermission();
  Future<String?> token();
  Stream<String> tokenRefresh();

  /// The text of a notification arrived with the app open (Android does not show it then).
  Stream<String> foreground();

  /// Where a tapped notification points (cns://novita): the one that opened the app, then the next.
  Future<Uri?> initialLink();
  Stream<Uri> openedLinks();
}

/// The phones of the account in Firestore (utenti/{uid}/telefoni/{phone}).
abstract class PhonesBackend {
  Future<bool> hasPhone(String uid, String phone);
  Future<void> savePhone(String uid, String phone, String token);
  Future<void> removePhone(String uid, String phone);
}

/// "Notifiche su questo telefono": when on, this phone is registered in the account with its
/// messaging token, and GitHub sends it the same notifications as ntfy. Off until the person
/// turns it on (Android asks for the permission then). Signing out takes this phone away.
class NotificationStore extends ChangeNotifier {
  NotificationStore(this._account, this._phones, this._push, {Future<String> Function()? phoneId})
      : _phoneId = phoneId ?? savedPhoneId {
    _account.addListener(_follow);
    _account.beforeSignOut.add(_forgetPhone);
    _refresh = _push.tokenRefresh().listen(_onToken);
    _follow();
  }

  final AccountStore _account;
  final PhonesBackend _phones;
  final PushBackend _push;
  final Future<String> Function() _phoneId;
  StreamSubscription<String>? _refresh;
  String? _uid;
  bool _disposed = false;

  bool on = false;
  bool loading = false;
  bool busy = false;
  String? problem;

  bool get ready => _uid != null && !loading;

  void _follow() {
    final user = _account.user;
    final uid = user != null && _account.admission == Admission.admitted ? user.uid : null;
    if (uid == _uid) return;
    _uid = uid;
    on = false;
    problem = null;
    if (uid != null) unawaited(_load(uid));
    _changed();
  }

  /// Whether this phone is registered; if it is, the token is sent again (it may have changed).
  Future<void> _load(String uid) async {
    loading = true;
    _changed();
    try {
      final phone = await _phoneId();
      final registered = await _phones.hasPhone(uid, phone);
      if (_uid != uid) return;
      if (registered && await _push.hasPermission()) {
        await _register(uid);
        on = true;
      } else if (registered) {
        // The permission was taken away in the phone's settings: nothing would arrive
        await _phones.removePhone(uid, phone);
        problem = 'Android non permette più le notifiche di CNS: riattivale qui sotto.';
      }
    } catch (err) {
      debugPrint('Notifiche non lette: $err');
      if (_uid == uid) problem = 'Non riesco a ricollegare questo telefono alle notifiche (${describeError(err)}).';
    } finally {
      loading = false;
      _changed();
    }
  }

  Future<void> _register(String uid) async {
    final String? token;
    try {
      token = await _token();
    } catch (err) {
      throw AccountError('Il telefono non dà il codice per le notifiche (${describeError(err)}). '
          'Controlla la connessione e riprova tra poco.');
    }
    if (token == null || token.isEmpty) throw const AccountError('Il telefono non ha dato il codice per le notifiche.');
    try {
      await _phones.savePhone(uid, await _phoneId(), token);
    } catch (err) {
      throw AccountError('Firebase non ha salvato questo telefono (${describeError(err)}).');
    }
  }

  /// The messaging token; asked a second time after a pause when the first try fails
  /// (Google's services may need a moment, e.g. right after the app opens).
  Future<String?> _token() async {
    try {
      return await _push.token();
    } catch (_) {
      await Future<void>.delayed(retryPause);
      return _push.token();
    }
  }

  /// The pause before asking the token again (none in the tests).
  @visibleForTesting
  static Duration retryPause = const Duration(seconds: 2);

  /// The switch: turning it on asks Android for the permission.
  Future<void> setOn(bool value) async {
    final uid = _uid;
    if (uid == null || value == on || busy) return;
    busy = true;
    problem = null;
    _changed();
    try {
      if (!value) {
        await _phones.removePhone(uid, await _phoneId());
      } else {
        if (!await _push.requestPermission()) {
          problem = 'Android non ha dato il permesso: attiva le notifiche di CNS dalle impostazioni del telefono, '
              'poi riprova.';
          return;
        }
        await _register(uid);
      }
      on = value;
    } on AccountError catch (err) {
      problem = err.message;
    } catch (err) {
      debugPrint('Notifiche non cambiate: $err');
      problem = 'Non riesco a salvare la scelta (${describeError(err)}). Controlla la connessione e riprova.';
    } finally {
      busy = false;
      _changed();
    }
  }

  void _onToken(String token) {
    final uid = _uid;
    if (uid == null || !on) return;
    unawaited(_phoneId()
        .then((id) => _phones.savePhone(uid, id, token))
        .catchError((Object err) => debugPrint('Nuovo codice notifiche non salvato: $err')));
  }

  /// Before signing out: this phone stops getting the account's notifications.
  Future<void> _forgetPhone() async {
    final uid = _uid;
    if (uid == null || !on) return;
    try {
      await _phones.removePhone(uid, await _phoneId());
    } catch (err) {
      debugPrint('Telefono non tolto: $err');
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _account.removeListener(_follow);
    _account.beforeSignOut.remove(_forgetPhone);
    _refresh?.cancel();
    super.dispose();
  }
}

/// A random name for this installation of the app, kept on the phone (the document's name
/// in utenti/{uid}/telefoni: 8-64 letters, digits, "-" or "_", as the rules want).
Future<String> savedPhoneId() async {
  final file = File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}telefono.txt');
  if (await file.exists()) {
    final id = (await file.readAsString()).trim();
    if (RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(id)) return id;
  }
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final random = Random.secure();
  final id = List.generate(22, (_) => chars[random.nextInt(chars.length)]).join();
  await file.writeAsString(id, flush: true);
  return id;
}

/// A short description of an error for the person (and for whoever helps them): the code of
/// Firebase's errors when there is one ("permission-denied"), otherwise the first words.
String describeError(Object err) {
  final text = '$err'.replaceAll(RegExp(r'\s+'), ' ').trim();
  final code = RegExp(r'\[[a-z_]+/([a-z-]+)\]').firstMatch(text)?.group(1);
  if (code != null) return code;
  return text.length > 120 ? '${text.substring(0, 120)}…' : text;
}
