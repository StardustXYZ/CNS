import 'deezer.dart';

/// One line of the import: what was asked, what Deezer found, and whether it goes in.
class ImportCandidate {
  ImportCandidate({required this.query, this.artist, this.exact = false, bool? selected})
      : selected = selected ?? (artist != null && exact);

  final String query; // the name written in the list ("" for the artists of a profile)
  final DeezerArtist? artist; // null: not found
  final bool exact; // Deezer's name is the same as the written one (or it comes from a profile)
  bool selected;
}

/// At most this many names in one import: one Deezer search each.
const maxImportNames = 200;

/// The names of a pasted list: one per line, without bullets or numbers, without repeats.
/// Commas stay (an artist can have one, as "Tyler, The Creator").
List<String> parseNames(String text) {
  final seen = <String>{};
  final names = <String>[];
  for (final raw in text.split(RegExp(r'[\r\n;]+'))) {
    final name = raw.replaceFirst(RegExp(r'^\s*(?:[-*•·]+|\d{1,3}[.)])\s*'), '').trim();
    if (name.isEmpty || !seen.add(normalize(name))) continue;
    names.add(name);
  }
  return names;
}

/// Looks for every name on Deezer, one at a time with a pause (Deezer limits how many
/// requests arrive together). Only an exact name is chosen by itself; a different name is
/// shown unchecked, to be checked by hand if it is right.
Future<List<ImportCandidate>> findByNames(
  DeezerApi deezer,
  List<String> names, {
  Duration pause = const Duration(milliseconds: 250),
  void Function(int done, int total)? onProgress,
  bool Function()? cancelled,
}) async {
  final found = <ImportCandidate>[];
  for (var i = 0; i < names.length; i++) {
    if (cancelled?.call() ?? false) break;
    if (i > 0) await Future<void>.delayed(pause);
    final name = names[i];
    final results = await deezer.searchArtists(name, limit: 10);
    final best = results.isEmpty ? null : results.first;
    found.add(ImportCandidate(query: name, artist: best, exact: best != null && isExactMatch(name, best)));
    onProgress?.call(i + 1, names.length);
  }
  return found;
}

/// The favourite artists of a public Deezer profile, from its link (also the share link of
/// the Deezer app) or its number.
Future<List<ImportCandidate>> findFromProfile(DeezerApi deezer, String input) async {
  var text = input.trim();
  if (isShortLink(text)) text = await deezer.resolveLink(text);
  final id = RegExp(r'^\d{1,20}$').hasMatch(text) ? text : profileIdFromLink(text);
  if (id == null) {
    throw const DeezerError('Non riconosco il link: deve essere quello di un profilo Deezer, '
        'come https://www.deezer.com/it/profile/123456.');
  }
  final List<DeezerArtist> artists;
  try {
    artists = await deezer.profileArtists(id);
  } on DeezerError catch (err) {
    if (err.message == 'Non trovato su Deezer.') throw const DeezerError(_privateProfile);
    rethrow;
  }
  if (artists.isEmpty) throw const DeezerError(_privateProfile);
  return [for (final a in artists) ImportCandidate(query: '', artist: a, exact: true)];
}

const _privateProfile = 'Non vedo artisti in questo profilo: forse è privato, oppure non ha artisti preferiti. '
    'Su Deezer, in Impostazioni › Privacy, il profilo deve essere pubblico.';
