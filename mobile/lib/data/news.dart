import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'account.dart';
import 'artists.dart' show LoadState;

/// A release GitHub told the account about (utenti/{uid}/novita), or an announced one
/// (utenti/{uid}/anteprime, "In arrivo"): the same fields, written by app/controllo.py and
/// app/anteprime.py.
@immutable
class NewsItem {
  const NewsItem({
    required this.id,
    required this.titolo,
    required this.artista,
    required this.artistaId,
    this.tipo = '',
    this.data = '',
    this.copertina = '',
    this.link = '',
    this.spotify = '',
    this.notificata,
  });

  factory NewsItem.fromMap(String id, Map<String, dynamic> d, {DateTime? notificata}) {
    String text(String key) => d[key] is String ? d[key] as String : '';
    return NewsItem(
      id: id,
      titolo: text('titolo'),
      artista: text('artista'),
      artistaId: '${d['artista_id'] ?? ''}',
      tipo: text('tipo'),
      data: text('data'),
      copertina: text('copertina'),
      link: text('link'), // Deezer for Novità, Apple Music for In arrivo
      spotify: text('spotify'),
      notificata: notificata,
    );
  }

  final String id;
  final String titolo;
  final String artista;
  final String artistaId;
  final String tipo;
  final String data; // "2026-11-20"
  final String copertina;
  final String link;
  final String spotify;
  final DateTime? notificata;
}

/// Firestore behind an interface, so the tests can do without it.
abstract class NewsBackend {
  /// The most recent Novità first (at most 200, as the web app).
  Stream<List<NewsItem>> watchNovita(String uid);
  Stream<List<NewsItem>> watchAnteprime(String uid);
  Future<void> removeNovita(String uid, List<String> ids);
}

/// When the Novità page was last opened on this phone (for the number on the menu).
abstract class SeenStore {
  Future<int> read();
  Future<void> write(int millis);
}

class FileSeenStore implements SeenStore {
  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/novita_vista.txt');

  @override
  Future<int> read() async {
    try {
      final file = await _file();
      return await file.exists() ? int.tryParse((await file.readAsString()).trim()) ?? 0 : 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<void> write(int millis) async {
    try {
      await (await _file()).writeAsString('$millis');
    } catch (_) {
      // Not essential: the number on the menu stays until the next time
    }
  }
}

class MemorySeenStore implements SeenStore {
  int value = 0;

  @override
  Future<int> read() async {
    await Future<void>.microtask(() {}); // as a real file: the answer comes later
    return value;
  }

  @override
  Future<void> write(int millis) async => value = millis;
}

/// "2026-11-15" for a day (local time).
String isoDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "esce oggi", "esce domani", "esce il 20/11/2026 (tra 5 giorni)".
String daysLeftLabel(String iso, DateTime today) {
  final todayIso = isoDay(today);
  if (iso == todayIso) return 'esce oggi';
  final days = DateTime.parse('${iso}T12:00:00').difference(DateTime.parse('${todayIso}T12:00:00')).inHours / 24;
  final n = days.round();
  if (n == 1) return 'esce domani';
  final p = iso.split('-');
  return 'esce il ${p[2]}/${p[1]}/${p[0]} (tra $n giorni)';
}

/// The account's Novità and In arrivo, kept up to date by Firestore while it is admitted.
class NewsStore extends ChangeNotifier {
  NewsStore(this._account, this._backend, this._seen, {DateTime Function()? now}) : _now = now ?? DateTime.now {
    _seen.read().then((v) {
      _lastSeen = v;
      _changed();
    });
    _account.addListener(_follow);
    _follow();
  }

  final AccountStore _account;
  final NewsBackend? _backend;
  final SeenStore _seen;
  final DateTime Function() _now;
  StreamSubscription<List<NewsItem>>? _novitaSub, _anteprimeSub;
  String? _uid;
  int _lastSeen = 0;
  bool _disposed = false;

  LoadState state = LoadState.idle;
  List<NewsItem> novita = const [];
  List<NewsItem> anteprime = const [];
  String? error;

  void _follow() {
    final user = _account.user;
    final uid = user != null && _account.admission == Admission.admitted ? user.uid : null;
    if (uid == _uid) return;
    _novitaSub?.cancel();
    _anteprimeSub?.cancel();
    _uid = uid;
    novita = const [];
    anteprime = const [];
    error = null;
    if (uid == null || _backend == null) {
      state = LoadState.idle;
    } else {
      state = LoadState.loading;
      void failed(Object err) {
        state = LoadState.error;
        error = 'Non riesco a leggere le Novità: $err';
        _changed();
      }

      _novitaSub = _backend.watchNovita(uid).listen((list) {
        novita = list;
        state = LoadState.ok;
        _changed();
      }, onError: failed);
      _anteprimeSub = _backend.watchAnteprime(uid).listen((list) {
        anteprime = list;
        _changed();
      }, onError: (Object err) => debugPrint('In arrivo non letti: $err'));
    }
    _changed();
  }

  /// The announced releases from today on (of one artist, or all), soonest first.
  List<NewsItem> comingSoon({String? artistId}) {
    final today = isoDay(_now());
    return anteprime.where((a) => a.data.compareTo(today) >= 0 && (artistId == null || a.artistaId == artistId)).toList()
      ..sort((a, b) {
        final byDate = a.data.compareTo(b.data);
        return byDate != 0 ? byDate : a.titolo.compareTo(b.titolo);
      });
  }

  DateTime get today => _now();

  /// How many Novità arrived since the page was last opened on this phone.
  int get unseen => novita.where((n) => (n.notificata?.millisecondsSinceEpoch ?? 0) > _lastSeen).length;

  /// The Novità page is open: the number on the menu goes away.
  void markSeen() {
    final now = _now().millisecondsSinceEpoch;
    if (unseen == 0 && _lastSeen != 0) return;
    _lastSeen = now;
    _seen.write(now);
    _changed();
  }

  Future<void> _run(Future<void> Function(NewsBackend b, String uid) action) async {
    final backend = _backend, uid = _uid;
    if (backend == null || uid == null) throw const AccountError('Fai prima l’accesso.');
    try {
      await action(backend, uid);
    } catch (err) {
      throw AccountError('Novità non cancellate: $err');
    }
  }

  Future<void> remove(String id) => _run((b, uid) => b.removeNovita(uid, [id]));

  /// "Svuota le Novità": the releases stay in the artists' discographies.
  Future<void> clear() => _run((b, uid) => b.removeNovita(uid, [for (final n in novita) n.id]));

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _account.removeListener(_follow);
    _novitaSub?.cancel();
    _anteprimeSub?.cancel();
    super.dispose();
  }
}
