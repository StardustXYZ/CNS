import 'dart:async';

import 'package:cns/data/account.dart';

/// Firebase as the rules would answer: "capo" (Google) is the administrator,
/// amico@example.com is in the list.
class FakeBackend implements AccountBackend {
  final _users = StreamController<AccountUser?>.broadcast();
  AccountUser? _current;
  List<String> allowed = ['amico@example.com'];
  final accounts = <String, String>{'amico@example.com': 'segreta1'}; // e-mail -> password
  final verifiedEmails = <String>{'amico@example.com'};
  final sent = <String>[];
  final remembered = <String, String>{}; // uid -> e-mail saved in the settings
  bool offline = false;

  static const capo = AccountUser(uid: 'capo', email: 'Capo@gmail.com', verified: true, name: 'Capo', google: true);

  void _set(AccountUser? u) {
    _current = u;
    _users.add(u);
  }

  AccountUser _emailUser(String email) =>
      AccountUser(uid: email.split('@').first, email: email, verified: verifiedEmails.contains(email));

  @override
  Stream<AccountUser?> userChanges() => _users.stream;

  @override
  Future<void> signInWithGoogle() async => _set(capo);

  @override
  Future<void> signInWithEmail(String email, String password) async {
    if (accounts[email] != password) throw const AccountError('Email o password sbagliate.');
    _set(_emailUser(email));
  }

  @override
  Future<void> register(String email, String password) async {
    if (accounts.containsKey(email)) throw const AccountError('Esiste già un account con questa email.');
    accounts[email] = password;
    sent.add('conferma:$email');
    _set(_emailUser(email));
  }

  @override
  Future<void> sendPasswordReset(String email) async => sent.add('password:$email');

  @override
  Future<void> sendVerification() async => sent.add('conferma:${_current!.email}');

  @override
  Future<AccountUser?> reload() async {
    final u = _current == null ? null : _emailUser(_current!.email);
    if (u != null) _current = u;
    return u;
  }

  @override
  Future<void> signOut() async => _set(null);

  @override
  Future<bool> isAdmitted(String uid) async {
    if (offline) throw Exception('unavailable');
    return uid == 'capo' || allowed.contains(_current?.email.toLowerCase());
  }

  @override
  Future<List<String>?> allowList() async => _current?.uid == 'capo' ? [...allowed] : null;

  @override
  Future<void> saveAllowList(List<String> emails) async => allowed = emails;

  @override
  Future<void> rememberEmail(String uid, String email) async => remembered[uid] = email;

  final deleted = <String>[];

  @override
  Future<void> deleteAccount() async {
    deleted.add(_current!.uid);
    _set(null);
  }
}

Future<void> settle() => Future<void>.delayed(Duration.zero);
