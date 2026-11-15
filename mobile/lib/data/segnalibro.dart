// The bookmark of Recuperando: which releases of an artist were listened to or skipped.
// Saved in the artist's document as "fatte": { <release key>: { s: "a" | "s", t: time } }
// ("a" = ascoltato, "s" = saltato), the same as web/segnalibro.js, so the web app and the
// Android app share it. The key is the one of the merged release (discografia.dart), so a
// new remix of a release already listened to does not come back in the queue.

import 'discografia.dart';

const listened = 'a';
const skipped = 's';

/// What a discography to catch up holds by default: compilations are left out.
const defaultKinds = ['album', 'ep', 'single', 'featuring'];

/// One mark of the bookmark.
class Mark {
  const Mark(this.state, this.time);

  /// From Firestore; anything unexpected becomes null and is ignored.
  static Mark? fromJson(Object? value) {
    if (value is! Map) return null;
    final s = value['s'];
    final t = value['t'];
    if (s != listened && s != skipped) return null;
    return Mark(s as String, t is num ? t.toInt() : 0);
  }

  Map<String, dynamic> toJson() => {'s': state, 't': time};

  final String state;
  final int time; // milliseconds since 1970, as Date.now() in the web app
}

typedef Fatte = Map<String, Mark>;

/// The queue of an artist: the releases of the chosen kinds, oldest first, split in done and to do.
class BookmarkQueue {
  BookmarkQueue._(this.all, this.pending, this.listenedCount, this.skippedCount);

  final List<ReleaseGroup> all;
  final List<ReleaseGroup> pending;
  final int listenedCount;
  final int skippedCount;

  ReleaseGroup? get next => pending.isEmpty ? null : pending.first;
  int get total => all.length;
  bool get finished => all.isNotEmpty && pending.isEmpty;
  int get done => listenedCount + skippedCount;
  int get percent => total == 0 ? 0 : (done * 100 / total).round();
}

BookmarkQueue queueOf(List<ReleaseGroup> groups, [Fatte fatte = const {}, List<String> chosen = defaultKinds]) {
  final all = arrange(groups.where((g) => chosen.contains(g.kind)).toList(), oldestFirst: true);
  return BookmarkQueue._(
    all,
    all.where((g) => !fatte.containsKey(g.key)).toList(),
    all.where((g) => fatte[g.key]?.state == listened).length,
    all.where((g) => fatte[g.key]?.state == skipped).length,
  );
}

/// A copy of [fatte] with one release marked as listened (or skipped).
Fatte mark(Fatte fatte, String key, String state, int now) => {...fatte, key: Mark(state, now)};

/// "Arrivato qui": every release of the queue up to this one (included) counts as listened;
/// the ones already marked keep their state.
Fatte markUpTo(List<ReleaseGroup> queueAll, String key, Fatte fatte, int now) {
  final index = queueAll.indexWhere((g) => g.key == key);
  if (index == -1) return fatte;
  final result = {...fatte};
  for (var i = 0; i <= index; i++) {
    // In order, so "undo" goes back one at a time
    result.putIfAbsent(queueAll[i].key, () => Mark(listened, now + i));
  }
  return result;
}

/// A copy of [fatte] without the most recent mark, and that mark's key (or null).
(Fatte, String?) undoLast(Fatte fatte) {
  String? lastKey;
  for (final entry in fatte.entries) {
    if (lastKey == null || entry.value.time >= fatte[lastKey]!.time) lastKey = entry.key;
  }
  if (lastKey == null) return (fatte, null);
  return ({...fatte}..remove(lastKey), lastKey);
}

/// Undo the mark of one release ("non l'ho ancora ascoltato").
Fatte unmark(Fatte fatte, String key) => {...fatte}..remove(key);

/// [fatte] as Firestore stores it.
Map<String, dynamic> fatteToJson(Fatte fatte) => {for (final e in fatte.entries) e.key: e.value.toJson()};

/// [fatte] from Firestore (the web app writes the same map).
Fatte fatteFromJson(Object? value) {
  if (value is! Map) return {};
  final out = <String, Mark>{};
  value.forEach((key, raw) {
    final m = Mark.fromJson(raw);
    if (key is String && m != null) out[key] = m;
  });
  return out;
}

// ------------------------------------------------------------------ free order: one tick per song

/// The songs ticked in each release, saved in the artist's document as "canzoni":
/// `{ <release key>: { <song key>: time } }`. When every song of a release is ticked, the
/// release is also marked as listened in "fatte", so the web app counts it too.
typedef Canzoni = Map<String, Map<String, int>>;

Canzoni canzoniFromJson(Object? value) {
  if (value is! Map) return {};
  final out = <String, Map<String, int>>{};
  value.forEach((release, songs) {
    if (release is! String || songs is! Map) return;
    final ticks = <String, int>{};
    songs.forEach((song, t) {
      if (song is String && t is num) ticks[song] = t.toInt();
    });
    if (ticks.isNotEmpty) out[release] = ticks;
  });
  return out;
}

Map<String, dynamic> canzoniToJson(Canzoni canzoni) => {for (final e in canzoni.entries) e.key: {...e.value}};

/// Ticks or unticks one song. Ticking the last one marks the release as listened; unticking a
/// song of a release listened to takes the mark away (the release is no longer complete).
(Canzoni, Fatte) toggleSong(
  Canzoni canzoni,
  Fatte fatte,
  String releaseKey,
  String songKey,
  List<String> allSongs,
  int now,
) {
  final ticks = {...?canzoni[releaseKey]};
  final nextFatte = {...fatte};
  if (ticks.containsKey(songKey)) {
    ticks.remove(songKey);
    if (nextFatte[releaseKey]?.state == listened) nextFatte.remove(releaseKey);
  } else {
    ticks[songKey] = now;
    if (allSongs.isNotEmpty && allSongs.every(ticks.containsKey)) nextFatte[releaseKey] = Mark(listened, now);
  }
  final next = {...canzoni};
  if (ticks.isEmpty) {
    next.remove(releaseKey);
  } else {
    next[releaseKey] = ticks;
  }
  return (next, nextFatte);
}
