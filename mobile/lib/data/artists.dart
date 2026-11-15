import 'dart:async';

import 'package:flutter/foundation.dart';

import 'account.dart';
import 'deezer.dart';
import 'discografia.dart' show kinds;
import 'segnalibro.dart';

/// The three lists of the web app: Controllare, Recuperando and the Archivio under Recuperando.
abstract final class Lists {
  static const controllare = 'controllare';
  static const recuperando = 'recuperando';
  static const archivio = 'archivio';

  static const labels = {controllare: 'Controllare', recuperando: 'Recuperando', archivio: 'Archivio'};
}

/// An artist saved in the account (utenti/{uid}/artisti/{deezerId}), as the web app writes it.
@immutable
class SavedArtist {
  const SavedArtist({
    required this.id,
    required this.nome,
    required this.lista,
    this.foto = '',
    this.link = '',
    this.fan = 0,
    this.nota = '',
    this.data = const {},
  });

  factory SavedArtist.fromMap(String id, Map<String, dynamic> d) => SavedArtist(
        id: id,
        nome: d['nome'] is String ? d['nome'] as String : '',
        lista: d['lista'] is String ? d['lista'] as String : Lists.controllare,
        foto: d['foto'] is String ? d['foto'] as String : '',
        link: d['link'] is String ? d['link'] as String : '',
        fan: d['fan'] is num ? (d['fan'] as num).toInt() : 0,
        nota: d['nota'] is String ? d['nota'] as String : '',
        data: d,
      );

  final String id;
  final String nome;
  final String lista;
  final String foto;
  final String link;
  final int fan;
  final String nota;
  final Map<String, dynamic> data; // everything, also the bookmark and the alerts

  /// The bookmark of Recuperando (web/segnalibro.js writes the same map).
  Fatte get fatte => fatteFromJson(data['fatte']);

  /// The kinds this artist's catch-up includes (compilations are out by default).
  List<String> get tipiRecupero => _kinds(data['tipi_recupero']) ?? defaultKinds;

  /// The kinds of release this person is told about for this artist (all, unless changed).
  List<String> get tipiAvviso => _kinds(data['tipi_avviso']) ?? kinds.keys.toList();

  /// "Quando finisco, sposta in automatico in Controllare".
  bool get autoSposta => data['auto_sposta'] == true;

  /// "Tieni qui" chosen at the end of the discography.
  bool get fineTenuta => data['fine_tenuta'] == true;

  static List<String>? _kinds(Object? value) {
    if (value is! List) return null;
    final list = [for (final k in value) if (k is String && kinds.containsKey(k)) k];
    return list.isEmpty ? null : list;
  }
}

/// Firestore behind an interface, so the tests can do without it.
abstract class ArtistsBackend {
  Stream<List<SavedArtist>> watch(String uid);

  /// Adds artists found on Deezer to a list, all together (the import adds many).
  Future<void> add(String uid, List<DeezerArtist> artists, String lista);
  Future<void> move(String uid, String id, String lista);

  /// Changes some fields (list, note, bookmark, alerts…); the others stay.
  Future<void> update(String uid, String id, Map<String, dynamic> fields);
  Future<void> remove(String uid, String id);
}

enum LoadState { idle, loading, ok, error }

/// The account's artists, kept up to date by Firestore while the account is admitted.
class ArtistStore extends ChangeNotifier {
  ArtistStore(this._account, this._backend) {
    _account.addListener(_follow);
    _follow();
  }

  final AccountStore _account;
  final ArtistsBackend? _backend;
  StreamSubscription<List<SavedArtist>>? _sub;
  String? _uid;

  LoadState state = LoadState.idle;
  List<SavedArtist> all = const [];
  String? error;

  /// Follows the account: starts watching when it is admitted, stops when it signs out.
  void _follow() {
    final user = _account.user;
    final uid = user != null && _account.admission == Admission.admitted ? user.uid : null;
    if (uid == _uid) return;
    _sub?.cancel();
    _uid = uid;
    all = const [];
    error = null;
    if (uid == null || _backend == null) {
      state = LoadState.idle;
    } else {
      state = LoadState.loading;
      _sub = _backend.watch(uid).listen((list) {
        all = list;
        state = LoadState.ok;
        error = null;
        notifyListeners();
      }, onError: (Object err) {
        state = LoadState.error;
        error = 'Non riesco a leggere le tue liste: $err';
        notifyListeners();
      });
    }
    notifyListeners();
  }

  /// The artists of a list, by name (as the web app: accents and capitals do not count).
  List<SavedArtist> inList(String lista) =>
      all.where((a) => a.lista == lista).toList()..sort((a, b) => normalize(a.nome).compareTo(normalize(b.nome)));

  int count(String lista) => all.where((a) => a.lista == lista).length;

  SavedArtist? byId(String id) {
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<void> _run(Future<void> Function(ArtistsBackend backend, String uid) action) async {
    final backend = _backend, uid = _uid;
    if (backend == null || uid == null) throw const AccountError('Fai prima l’accesso.');
    try {
      await action(backend, uid);
    } on AccountError {
      rethrow;
    } catch (err) {
      throw AccountError('Modifica non salvata: $err');
    }
  }

  /// Adds an artist found on Deezer, or moves it to [lista] if it is already saved (keeping its note).
  Future<void> add(DeezerArtist artist, String lista) => _run((b, uid) async {
        if (byId(artist.id) != null) {
          await b.move(uid, artist.id, lista);
        } else {
          await b.add(uid, [artist], lista);
        }
      });

  /// Adds many artists at once; the ones already saved are left where they are.
  /// Returns how many were added.
  Future<int> addMany(List<DeezerArtist> artists, String lista) async {
    final seen = <String>{};
    final fresh = [for (final a in artists) if (byId(a.id) == null && seen.add(a.id)) a];
    if (fresh.isEmpty) return 0;
    await _run((b, uid) => b.add(uid, fresh, lista));
    return fresh.length;
  }

  Future<void> move(String id, String lista) => _run((b, uid) => b.move(uid, id, lista));
  Future<void> update(String id, Map<String, dynamic> fields) => _run((b, uid) => b.update(uid, id, fields));
  Future<void> remove(String id) => _run((b, uid) => b.remove(uid, id));

  @override
  void dispose() {
    _account.removeListener(_follow);
    _sub?.cancel();
    super.dispose();
  }
}
