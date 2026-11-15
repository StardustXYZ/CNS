// Backup of one person's CNS data as a JSON file: the same format as web/copia.js
// ("cns-copia", version 1), so a file made by the web app is restored in the Android app and
// the other way round. The file holds the artists (lists, notes, bookmark, songs ticked, alert
// kinds), the ntfy topic, the Novità and the announced releases. Restoring brings back the
// artists and the topic; the Novità and "In arrivo" are written only by GitHub, so they stay in
// the file as a record. Pure functions, no network.

import 'dart:convert';

const backupFormat = 'cns-copia';
const backupVersion = 1;
const _lists = ['controllare', 'recuperando', 'archivio'];
// The fields of an artist that a restore writes back (the same list as the web app)
const _artistFields = [
  'nome', 'foto', 'link', 'fan', 'lista', 'nota', 'fatte', 'canzoni', //
  'tipi_recupero', 'tipi_avviso', 'auto_sposta', 'fine_tenuta',
];
final _topic = RegExp(r'^[A-Za-z0-9_-]{0,64}$');

/// A problem with the file, with words for the user (the same as the web app).
class BackupError implements Exception {
  const BackupError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Dates as ISO text (as JSON wants them), everything else as it is.
Object? _plain(Object? value) {
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is List) return [for (final v in value) _plain(v)];
  if (value is Map) return {for (final e in value.entries) '${e.key}': _plain(e.value)};
  return value;
}

/// The backup object, ready for jsonEncode. [artists] are the documents with their "id".
Map<String, dynamic> buildBackup({
  required List<Map<String, dynamic>> artists,
  Map<String, dynamic> settings = const {},
  List<Map<String, dynamic>> novita = const [],
  List<Map<String, dynamic>> anteprime = const [],
  String email = '',
  required DateTime now,
}) =>
    {
      'formato': backupFormat,
      'versione': backupVersion,
      'salvata': now.toUtc().toIso8601String(),
      'account': email,
      'impostazioni': {'ntfy': settings['ntfy'] is String ? settings['ntfy'] : ''},
      'artisti': [for (final a in artists) _plain(a)],
      'novita': [for (final n in novita) _plain(n)],
      'in_arrivo': [for (final n in anteprime) _plain(n)],
    };

/// The text of the file, indented a little as the web app writes it.
String backupText(Map<String, dynamic> backup) => const JsonEncoder.withIndent(' ').convert(backup);

/// "cns-copia-2026-11-13.json".
String backupFileName(DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'cns-copia-${now.year}-${two(now.month)}-${two(now.day)}.json';
}

/// What a backup file holds, ready to restore.
class ParsedBackup {
  const ParsedBackup({required this.artists, required this.ntfy, required this.skipped, required this.saved});

  final List<(String, Map<String, dynamic>)> artists; // (Deezer id, fields)
  final String? ntfy; // null when missing or not valid
  final int skipped; // artists left out because not valid
  final String saved; // when the copy was made
}

/// Reads a backup file; the artists not valid are left out, as the web app does.
ParsedBackup parseBackup(String text) {
  final Object? data;
  try {
    data = jsonDecode(text);
  } on FormatException {
    throw const BackupError('il file non è una copia di CNS (non è JSON)');
  }
  if (data is! Map || data['formato'] != backupFormat || data['artisti'] is! List) {
    throw const BackupError('il file non è una copia di CNS');
  }
  final version = data['versione'];
  if ((version is num ? version : num.tryParse('$version') ?? 0) > backupVersion) {
    throw const BackupError("la copia è di una versione più nuova di CNS: aggiorna l'app e riprova");
  }
  final raw = data['artisti'] as List;
  final artists = <(String, Map<String, dynamic>)>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final id = '${item['id'] ?? ''}';
    final nome = item['nome'];
    if (!RegExp(r'^[0-9]{1,20}$').hasMatch(id) || nome is! String || nome.trim().isEmpty || !_lists.contains(item['lista'])) {
      continue;
    }
    final fields = <String, dynamic>{
      for (final k in _artistFields)
        if (item.containsKey(k) && item[k] != null) k: item[k],
    };
    fields['nome'] = nome.length > 200 ? nome.substring(0, 200) : nome;
    final nota = fields['nota'] is String ? fields['nota'] as String : '';
    fields['nota'] = nota.length > 500 ? nota.substring(0, 500) : nota;
    artists.add((id, fields));
  }
  final settings = data['impostazioni'];
  final topic = settings is Map ? settings['ntfy'] : null;
  return ParsedBackup(
    artists: artists,
    ntfy: topic is String && _topic.hasMatch(topic) ? topic : null,
    skipped: raw.length - artists.length,
    saved: data['salvata'] is String ? data['salvata'] as String : '',
  );
}
