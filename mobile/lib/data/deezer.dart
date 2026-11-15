import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'discografia.dart';

/// An artist as Deezer describes it.
class DeezerArtist {
  const DeezerArtist({
    required this.id,
    required this.name,
    this.picture = '',
    this.fans = 0,
    this.albums = 0,
    this.link = '',
  });

  factory DeezerArtist.fromApi(Map<String, dynamic> hit) => DeezerArtist(
        id: '${hit['id']}',
        name: (hit['name'] as String?) ?? '',
        picture: (hit['picture_big'] ?? hit['picture_medium'] ?? hit['picture'] ?? '') as String,
        fans: (hit['nb_fan'] as num?)?.toInt() ?? 0,
        albums: (hit['nb_album'] as num?)?.toInt() ?? 0,
        link: (hit['link'] as String?) ?? 'https://www.deezer.com/artist/${hit['id']}',
      );

  final String id;
  final String name;
  final String picture;
  final int fans;
  final int albums;
  final String link;
}

/// A problem with Deezer, with words for the user.
class DeezerError implements Exception {
  const DeezerError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Deezer behind an interface, so the tests can do without the network.
abstract class DeezerApi {
  Future<List<DeezerArtist>> searchArtists(String query, {int limit = 15});
  Future<DeezerArtist> artist(String id);

  /// The favourite artists of a public Deezer profile (all pages).
  Future<List<DeezerArtist>> profileArtists(String profileId);

  /// Where a short link (link.deezer.com/…) leads; other links come back as they are.
  Future<String> resolveLink(String link);

  /// Every release of an artist's discography (all pages), as Deezer lists them.
  Future<List<Release>> discography(String artistId);
}

/// The public Deezer API, without a key. From the phone it answers directly (no JSONP as
/// in the web app). On "quota exceeded" (code 4) it waits and tries again, as the Python side.
class DeezerClient implements DeezerApi {
  DeezerClient([http.Client? client]) : _http = client ?? http.Client();

  static const _api = 'https://api.deezer.com';
  static const _timeout = Duration(seconds: 12);
  static const _pageSize = 100;
  static const _maxPages = 20; // a safety stop: 2000 favourite artists
  static const _maxDiscographyPages = 50; // a safety stop: 5000 releases, as the web app

  final http.Client _http;

  Future<Map<String, dynamic>> _get(String path, [Map<String, String> params = const {}]) async {
    final uri = Uri.parse('$_api$path').replace(queryParameters: params.isEmpty ? null : params);
    for (var attempt = 0;; attempt++) {
      final http.Response response;
      try {
        response = await _http.get(uri).timeout(_timeout);
      } on TimeoutException {
        throw const DeezerError('Deezer non risponde. Riprova tra poco.');
      } on SocketException {
        throw const DeezerError('Deezer non raggiungibile: controlla la connessione.');
      } on http.ClientException {
        throw const DeezerError('Deezer non raggiungibile: controlla la connessione.');
      }
      if (response.statusCode != 200) throw DeezerError('Deezer ha risposto con un errore (${response.statusCode}).');
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) throw const DeezerError('Risposta di Deezer non valida.');
      final error = data['error'];
      if (error is Map) {
        if (error['code'] == 4 && attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 1500 * (attempt + 1))); // too many requests
          continue;
        }
        if (error['code'] == 800) throw const DeezerError('Non trovato su Deezer.'); // "no data"
        throw DeezerError('Errore di Deezer: ${error['message'] ?? error['type'] ?? 'sconosciuto'}.');
      }
      return data;
    }
  }

  static List<Map<String, dynamic>> _items(Map<String, dynamic> data) =>
      [for (final item in (data['data'] as List? ?? const [])) if (item is Map<String, dynamic>) item];

  @override
  Future<List<DeezerArtist>> searchArtists(String query, {int limit = 15}) async {
    final data = await _get('/search/artist', {'q': query, 'limit': '$limit'});
    return rankArtists(query, _items(data).map(DeezerArtist.fromApi).toList());
  }

  @override
  Future<DeezerArtist> artist(String id) async => DeezerArtist.fromApi(await _get('/artist/${Uri.encodeComponent(id)}'));

  @override
  Future<List<DeezerArtist>> profileArtists(String profileId) async {
    final found = <DeezerArtist>[];
    for (var page = 0; page < _maxPages; page++) {
      final data = await _get('/user/${Uri.encodeComponent(profileId)}/artists',
          {'limit': '$_pageSize', 'index': '${page * _pageSize}'});
      final items = _items(data);
      found.addAll(items.map(DeezerArtist.fromApi));
      if (data['next'] == null || items.isEmpty) break;
    }
    return found;
  }

  @override
  Future<List<Release>> discography(String artistId) async {
    final found = <Release>[];
    for (var page = 0; page < _maxDiscographyPages; page++) {
      final data = await _get('/artist/${Uri.encodeComponent(artistId)}/albums',
          {'limit': '$_pageSize', 'index': '${page * _pageSize}'});
      final items = _items(data);
      found.addAll(items.map(Release.fromApi));
      if (data['next'] == null || items.isEmpty) break;
    }
    return found;
  }

  @override
  Future<String> resolveLink(String link) async {
    var uri = Uri.tryParse(link.trim());
    if (uri == null || !isShortLink(link)) return link;
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      for (var hop = 0; hop < 5; hop++) {
        final request = await client.getUrl(uri!)..followRedirects = false;
        final response = await request.close().timeout(_timeout);
        await response.drain<void>();
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (!response.isRedirect || location == null) break;
        uri = uri.resolve(location);
      }
      return uri.toString();
    } catch (_) {
      throw const DeezerError('Non riesco ad aprire il link di Deezer: controlla la connessione.');
    } finally {
      client.close();
    }
  }
}

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a',
  'ç': 'c', 'ć': 'c', 'č': 'c', 'ď': 'd', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e',
  'ė': 'e', 'ę': 'e', 'ě': 'e', 'ğ': 'g', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
  'į': 'i', 'ı': 'i', 'ľ': 'l', 'ł': 'l', 'ñ': 'n', 'ń': 'n', 'ň': 'n', 'ò': 'o', 'ó': 'o',
  'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ő': 'o', 'ŕ': 'r', 'ř': 'r', 'ś': 's',
  'š': 's', 'ş': 's', 'ș': 's', 'ť': 't', 'ţ': 't', 'ț': 't', 'ù': 'u', 'ú': 'u', 'û': 'u',
  'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u', 'ý': 'y', 'ÿ': 'y', 'ź': 'z', 'ż': 'z',
  'ž': 'z', 'ß': 'ss', 'æ': 'ae', 'œ': 'oe',
};

/// Lowercase, no accents, no punctuation: "Beyoncé" and "beyonce" match (as web/deezer.js).
String normalize(String text) {
  final folded = text.toLowerCase().split('').map((c) => _accents[c] ?? c).join();
  return folded.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// The artist code in a Deezer link ("https://www.deezer.com/it/artist/12948083?..."), or null.
String? artistIdFromLink(String text) =>
    RegExp(r'deezer\.com/(?:[a-z]{2}(?:-[a-z]{2})?/)?artist/(\d{1,20})', caseSensitive: false).firstMatch(text)?.group(1);

/// The profile code in a Deezer link ("https://www.deezer.com/it/profile/2529"), or null.
String? profileIdFromLink(String text) =>
    RegExp(r'deezer\.com/(?:[a-z]{2}(?:-[a-z]{2})?/)?(?:profile|user)/(\d{1,20})', caseSensitive: false)
        .firstMatch(text)
        ?.group(1);

/// The share links of the Deezer app ("https://link.deezer.com/s/…", "deezer.page.link/…").
bool isShortLink(String text) => RegExp(r'(link\.deezer\.com|deezer\.page\.link)/', caseSensitive: false).hasMatch(text);

/// Results in the best order: the exact name with the most fans first (Deezer does not
/// always put the right artist first: "Amy Lee" the singer is fifth), then Deezer's order.
List<DeezerArtist> rankArtists(String query, List<DeezerArtist> artists) {
  final wanted = normalize(query);
  final exact = artists.where((a) => normalize(a.name) == wanted).toList()..sort((a, b) => b.fans.compareTo(a.fans));
  return [...exact, ...artists.where((a) => !exact.contains(a))];
}

/// Whether the first of the ranked results has exactly the searched name.
bool isExactMatch(String query, DeezerArtist artist) => normalize(query) == normalize(artist.name);

/// "1,2 mln di fan", "136.074 fan", "1 fan" (as web/deezer.js).
String fansLabel(int fans) {
  if (fans >= 1000000) {
    final millions = (fans / 100000).round() / 10;
    final text = millions == millions.roundToDouble() ? '${millions.toInt()}' : '$millions'.replaceAll('.', ',');
    return '$text mln di fan';
  }
  return '${thousands(fans)} fan';
}

/// 136074 -> "136.074".
String thousands(int n) {
  final digits = '$n';
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return out.toString();
}
