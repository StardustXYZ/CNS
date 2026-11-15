// An artist's discography from Deezer, with the duplicates merged.
// Deezer lists every version as a separate release: remixes, deluxe and explicit/clean
// editions, acoustic and live versions. Here they become "versions" of one release, shown
// under the original. The same rules as web/discografia.js and app/services/discografia.py,
// tested with the same examples (tests/fixtures/doppioni.json).

import 'deezer.dart' show normalize;

/// A kind of release, with its name in the app.
class Kind {
  const Kind(this.label, this.plural);

  final String label;
  final String plural;
}

const kinds = {
  'album': Kind('Album', 'Album'),
  'ep': Kind('EP', 'EP'),
  'single': Kind('Singolo', 'Singoli'),
  'featuring': Kind('Featuring', 'Featuring'),
  'compile': Kind('Raccolta', 'Raccolte'),
};

/// One release as Deezer gives it (artist/{id}/albums).
class Release {
  const Release({
    required this.id,
    required this.title,
    this.type = 'album',
    this.date = '',
    this.cover = '',
    this.link = '',
    this.explicit = false,
  });

  factory Release.fromApi(Map<String, dynamic> hit) {
    final raw = hit['release_date'];
    final date = raw is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw) && raw != '0000-00-00' ? raw : '';
    return Release(
      id: '${hit['id']}',
      title: (hit['title'] as String?) ?? '',
      type: '${hit['record_type'] ?? hit['type'] ?? 'album'}'.toLowerCase(),
      date: date,
      cover: (hit['cover_medium'] ?? hit['cover_big'] ?? hit['cover'] ?? '') as String,
      link: (hit['link'] as String?) ?? 'https://www.deezer.com/album/${hit['id']}',
      explicit: hit['explicit_lyrics'] == true,
    );
  }

  /// The copy saved on the phone (the same fields as the web app's copy).
  factory Release.fromJson(Map<String, dynamic> j) => Release(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        type: '${j['type'] ?? 'album'}',
        date: '${j['date'] ?? ''}',
        cover: '${j['cover'] ?? ''}',
        link: '${j['link'] ?? ''}',
        explicit: j['explicit'] == true,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'type': type, 'date': date, 'cover': cover, 'link': link, 'explicit': explicit};

  final String id;
  final String title;
  final String type;
  final String date; // "2026-11-06", or "" when unknown
  final String cover;
  final String link;
  final bool explicit;
}

/// A release with its versions merged under it.
class ReleaseGroup {
  const ReleaseGroup({required this.key, required this.kind, required this.main, required this.versions});

  final String key;
  final String kind;
  final Release main;
  final List<Release> versions;

  String get date => main.date;
}

// Words that mark a version of the same release, inside "( )", "[ ]" or after " - "
final _versionWords = RegExp(
  r'\b(deluxe|edition|version|explicit|clean|remaster(ed)?|bonus|expanded|extended|anniversary|remix(es)?|mix|'
  r'sped up|slowed|reverb|acoustic|instrumental|without dialogue|demo|live|feat\.?|ft\.?|featuring|with)\b',
  caseSensitive: false,
);
// "(feat. X)", "ft. X", "featuring X", "(with X)": the names after it are the guests
final _feat = RegExp(r'(?:\b(?:feat|ft)\b\.?|\bfeaturing\b|[(\[]\s*with\b)\s*([^)\]]+)', caseSensitive: false);
final _lastMark = RegExp(r'\s*(?:\(([^()]*)\)|\[([^\[\]]*)\]|\s-\s([^-]+))\s*$');

/// The title without the version marks: "Sweet but Psycho (Leon Lour Remix)" -> "Sweet but Psycho".
String baseTitle(String title) {
  var t = title.trim();
  while (true) {
    final match = _lastMark.firstMatch(t);
    if (match == null) return t;
    final inside = match.group(1) ?? match.group(2) ?? match.group(3) ?? '';
    if (!_versionWords.hasMatch(inside)) return t;
    final shorter = t.substring(0, match.start).trim();
    if (shorter.isEmpty) return t;
    t = shorter;
  }
}

/// True when the artist is a guest named in the title, e.g. "BURN (feat. Ava Max)".
bool isFeaturing(String title, String artistName) {
  final wanted = normalize(artistName);
  if (wanted.isEmpty) return false;
  for (final m in _feat.allMatches(title)) {
    if (' ${normalize(m.group(1) ?? '')} '.contains(' $wanted ')) return true;
  }
  return false;
}

/// The kind shown in the app: album, ep, single, featuring or compile.
String kindOf(Release release, String artistName) {
  if (isFeaturing(release.title, artistName)) return 'featuring';
  return kinds.containsKey(release.type) ? release.type : 'album';
}

/// The key shared by all the versions of a release (the same as groupKey() of the web app
/// and group_key() of the check on GitHub). It is also the key of the bookmark.
String groupKey(Release release, String artistName) {
  final kind = kindOf(release, artistName);
  final family = kind == 'ep' ? 'album' : kind; // an EP and its deluxe album are the same release
  return '$family|${normalize(baseTitle(release.title))}';
}

int _byDateThenTitle(Release a, Release b) {
  final byDate = (a.date.isEmpty ? '9999' : a.date).compareTo(b.date.isEmpty ? '9999' : b.date);
  return byDate != 0 ? byDate : a.title.compareTo(b.title);
}

/// Merge the versions: same title without the version marks, same kind (an album and the
/// single with its name stay apart). The original is the one without marks, else the oldest.
List<ReleaseGroup> groupReleases(List<Release> releases, String artistName) {
  final groups = <String, List<Release>>{};
  for (final r in releases) {
    (groups[groupKey(r, artistName)] ??= []).add(r);
  }
  return [
    for (final entry in groups.entries)
      () {
        final byDate = [...entry.value]..sort(_byDateThenTitle);
        final main = byDate.firstWhere((r) => r.title.trim() == baseTitle(r.title), orElse: () => byDate.first);
        return ReleaseGroup(
          key: entry.key,
          kind: kindOf(main, artistName),
          main: main,
          versions: [for (final r in byDate) if (!identical(r, main)) r],
        );
      }(),
  ];
}

/// How many releases of each kind: {album: 3, single: 40, …}.
Map<String, int> countKinds(List<ReleaseGroup> groups) {
  final counts = <String, int>{};
  for (final g in groups) {
    counts[g.kind] = (counts[g.kind] ?? 0) + 1;
  }
  return counts;
}

/// The groups of one kind ("" = all), by date: oldest first or newest first; undated last.
List<ReleaseGroup> arrange(List<ReleaseGroup> groups, {String kind = '', bool oldestFirst = false}) {
  final chosen = kind.isEmpty ? [...groups] : groups.where((g) => g.kind == kind).toList();
  chosen.sort((a, b) {
    if (a.date.isEmpty != b.date.isEmpty) return a.date.isNotEmpty ? -1 : 1;
    var order = a.date.compareTo(b.date);
    if (order == 0) order = a.main.title.compareTo(b.main.title);
    return oldestFirst ? order : -order;
  });
  return chosen;
}

/// "06/11/2026" from "2026-11-06"; "data sconosciuta" without a date.
String dateLabel(String iso) {
  if (iso.isEmpty) return 'data sconosciuta';
  final parts = iso.split('-');
  return '${parts[2]}/${parts[1]}/${parts[0]}';
}

/// Spotify's search page for the release; on Android it opens the Spotify app (no exact link
/// without its API).
String spotifySearchUrl(String artist, String title) =>
    'https://open.spotify.com/search/${Uri.encodeComponent('$artist $title'.trim())}';
