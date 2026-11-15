import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'account.dart';
import 'artists.dart';
import 'copia.dart';
import 'news.dart';

/// Firestore for the backup: the account's settings and the restore of the artists.
abstract class BackupBackend {
  Future<Map<String, dynamic>> readSettings(String uid);

  /// Writes the artists as they are in the copy: the ones with the same code are replaced.
  Future<void> restoreArtists(String uid, List<(String, Map<String, dynamic>)> artists);
  Future<void> saveSettings(String uid, Map<String, dynamic> fields);
}

/// The phone's files behind an interface, so the tests can do without Android.
abstract class BackupFiles {
  /// Asks where to save the file; false when the person closes the window.
  Future<bool> save(String fileName, Uint8List bytes);

  /// Lets the person choose a file and gives back its text (null when closed).
  Future<String?> pick();
}

/// Android's "save as" and "open" windows.
class PickerFiles implements BackupFiles {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async =>
      await FilePicker.saveFile(
        dialogTitle: 'Salva la copia di CNS',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      ) !=
      null;

  @override
  Future<String?> pick() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Scegli una copia di CNS',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }
}

/// A Novità or In arrivo as it goes in the file (the same fields GitHub writes).
Map<String, dynamic> newsToMap(NewsItem n) => {
      'id': n.id,
      'artista': n.artista,
      'artista_id': n.artistaId,
      'titolo': n.titolo,
      'tipo': n.tipo,
      'data': n.data,
      'copertina': n.copertina,
      'link': n.link,
      'spotify': n.spotify,
      if (n.notificata != null) 'notificata': n.notificata,
    };

/// "Salva la copia" and "Ripristina da una copia" of Impostazioni.
class BackupService {
  BackupService(this._account, this._artists, this._news, this._backend, this._files, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final AccountStore _account;
  final ArtistStore _artists;
  final NewsStore _news;
  final BackupBackend? _backend;
  final BackupFiles _files;
  final DateTime Function() _now;

  String get _uid {
    final user = _account.user;
    if (user == null || _backend == null || _account.admission != Admission.admitted) {
      throw const AccountError('Fai prima l’accesso.');
    }
    return user.uid;
  }

  /// Makes the file and asks where to save it. Returns the number of artists, or null when
  /// the person closed the window.
  Future<int?> save() async {
    final uid = _uid;
    final Map<String, dynamic> settings;
    try {
      settings = await _backend!.readSettings(uid);
    } catch (err) {
      throw AccountError('Impostazioni non lette: $err');
    }
    final now = _now();
    final backup = buildBackup(
      artists: [for (final a in _artists.all) {'id': a.id, ...a.data}],
      settings: settings,
      novita: [for (final n in _news.novita) newsToMap(n)],
      anteprime: [for (final n in _news.anteprime) newsToMap(n)],
      email: _account.user?.email ?? '',
      now: now,
    );
    final saved = await _files.save(backupFileName(now), Uint8List.fromList(utf8.encode(backupText(backup))));
    return saved ? _artists.all.length : null;
  }

  /// Lets the person choose a file and reads it (BackupError when it is not a valid copy).
  Future<ParsedBackup?> choose() async {
    final text = await _files.pick();
    return text == null ? null : parseBackup(text);
  }

  /// Writes back the artists and the ntfy topic of the copy.
  Future<void> restore(ParsedBackup backup) async {
    final uid = _uid;
    try {
      await _backend!.restoreArtists(uid, backup.artists);
      final topic = backup.ntfy;
      if (topic != null && topic.isNotEmpty) await _backend.saveSettings(uid, {'ntfy': topic});
    } catch (err) {
      throw AccountError('Copia non ripristinata: $err');
    }
  }
}
