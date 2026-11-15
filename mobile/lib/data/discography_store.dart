import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'artists.dart' show LoadState;
import 'deezer.dart';
import 'discografia.dart';

/// The discography of one artist: the copy on the phone at once, then Deezer when it is old.
class DiscoEntry {
  LoadState state = LoadState.idle;
  List<Release> releases = const [];
  DateTime? savedAt;
  String? error; // the last problem with Deezer (the saved copy may still be shown)
  bool loading = false;
  DateTime? failedAt;
  bool read = false; // the copy on the phone was looked for
}

/// Where the discographies are kept on the phone (memory in the tests).
abstract class DiscoCache {
  Future<(List<Release>, DateTime)?> read(String artistId);
  Future<void> write(String artistId, List<Release> releases, DateTime savedAt);
}

/// One JSON file per artist in the app's own folder, with the same fields as the web copy.
class FileDiscoCache implements DiscoCache {
  Directory? _dir;

  Future<File> _file(String artistId) async {
    _dir ??= Directory('${(await getApplicationSupportDirectory()).path}/discografie');
    return File('${_dir!.path}/${artistId.replaceAll(RegExp(r'[^0-9]'), '')}.json');
  }

  @override
  Future<(List<Release>, DateTime)?> read(String artistId) async {
    try {
      final file = await _file(artistId);
      if (!await file.exists()) return null;
      final saved = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final releases = [for (final r in saved['releases'] as List) Release.fromJson(r as Map<String, dynamic>)];
      return (releases, DateTime.parse(saved['savedAt'] as String));
    } catch (err) {
      debugPrint('Copia della discografia non letta: $err');
      return null; // broken copy: it is asked again to Deezer
    }
  }

  @override
  Future<void> write(String artistId, List<Release> releases, DateTime savedAt) async {
    try {
      final file = await _file(artistId);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'savedAt': savedAt.toUtc().toIso8601String(),
        'releases': [for (final r in releases) r.toJson()],
      }));
    } catch (err) {
      debugPrint('Copia della discografia non salvata: $err'); // asked again next time
    }
  }
}

class MemoryDiscoCache implements DiscoCache {
  final saved = <String, (List<Release>, DateTime)>{};

  @override
  Future<(List<Release>, DateTime)?> read(String artistId) async => saved[artistId];

  @override
  Future<void> write(String artistId, List<Release> releases, DateTime savedAt) async =>
      saved[artistId] = (releases, savedAt);
}

/// The discographies asked to Deezer, shared by the artist page and the Recuperando list.
class DiscographyStore extends ChangeNotifier {
  DiscographyStore(this._deezer, this._cache, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const fresh = Duration(hours: 6); // as the web app: asked again to Deezer after this
  static const _retryAfter = Duration(minutes: 1); // no retry loop when Deezer is down
  static const _parallel = 2; // the Recuperando list asks many: a few at a time

  final DeezerApi _deezer;
  final DiscoCache _cache;
  final DateTime Function() _now;
  final _entries = <String, DiscoEntry>{};
  final _waiting = <String>[];
  int _running = 0;
  bool _disposed = false;

  DiscoEntry entry(String artistId) => _entries[artistId] ??= DiscoEntry();

  /// Makes sure the discography is there and recent; safe to call while building.
  DiscoEntry ensure(String artistId, {bool force = false}) {
    final e = entry(artistId);
    if (e.loading || _waiting.contains(artistId)) return e;
    if (!e.read) {
      e.read = true;
      e.loading = true;
      _cache.read(artistId).then((saved) {
        if (saved != null && e.releases.isEmpty) {
          e
            ..releases = saved.$1
            ..savedAt = saved.$2
            ..state = LoadState.ok;
        }
        e.loading = false;
        _changed();
        ensure(artistId, force: force);
      });
      return e;
    }
    final now = _now();
    final isFresh = e.savedAt != null && now.difference(e.savedAt!) < fresh;
    final justFailed = e.failedAt != null && now.difference(e.failedAt!) < _retryAfter;
    if ((isFresh || justFailed) && !force) return e;
    if (e.releases.isEmpty) e.state = LoadState.loading;
    _waiting.add(artistId);
    scheduleMicrotask(_next);
    return e;
  }

  void _next() {
    while (_running < _parallel && _waiting.isNotEmpty) {
      final artistId = _waiting.removeAt(0);
      _running++;
      _fetch(artistId).whenComplete(() {
        _running--;
        _next();
      });
    }
  }

  Future<void> _fetch(String artistId) async {
    final e = entry(artistId)..loading = true;
    _changed();
    try {
      final releases = await _deezer.discography(artistId);
      final savedAt = _now();
      e
        ..releases = releases
        ..savedAt = savedAt
        ..state = LoadState.ok
        ..error = null
        ..failedAt = null;
      await _cache.write(artistId, releases, savedAt);
    } catch (err) {
      // With a saved copy, keep showing it; otherwise explain
      e
        ..state = e.releases.isEmpty ? LoadState.error : LoadState.ok
        ..error = '$err'
        ..failedAt = _now();
    } finally {
      e.loading = false;
      _changed();
    }
  }

  final _tracks = <String, Future<List<Track>>>{};
  final _related = <String, Future<List<DeezerArtist>>>{};

  /// The songs of a release, asked to Deezer once while the app is open (a failure is retried).
  Future<List<Track>> tracks(String releaseId) =>
      _tracks[releaseId] ??= _deezer.tracks(releaseId).catchError((Object err) {
        _tracks.remove(releaseId);
        throw err;
      });

  /// The similar artists, asked to Deezer once while the app is open.
  Future<List<DeezerArtist>> related(String artistId) =>
      _related[artistId] ??= _deezer.related(artistId).catchError((Object err) {
        _related.remove(artistId);
        throw err;
      });

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
