import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'artists.dart';
import 'discografia.dart';
import 'discography_store.dart';
import 'news.dart';
import 'segnalibro.dart';

/// The two home screen widgets (android/app/src/main/kotlin/…/UltimeUsciteWidget.kt and
/// ProssimoWidget.kt) behind an interface, so the tests can do without Android.
abstract class WidgetBridge {
  Future<void> save(Map<String, String?> data);
  Future<void> refresh();

  /// The widget the app was opened from (cns://novita, cns://artista/{id}…), then the next taps.
  Future<Uri?> initialLink();
  Stream<Uri?> get links;
}

class HomeWidgetBridge implements WidgetBridge {
  static const _providers = ['it.stardustxyz.cns.UltimeUsciteWidget', 'it.stardustxyz.cns.ProssimoWidget'];

  @override
  Future<void> save(Map<String, String?> data) async {
    for (final e in data.entries) {
      await HomeWidget.saveWidgetData<String>(e.key, e.value);
    }
  }

  @override
  Future<void> refresh() async {
    for (final name in _providers) {
      await HomeWidget.updateWidget(qualifiedAndroidName: name);
    }
  }

  @override
  Future<Uri?> initialLink() => HomeWidget.initiallyLaunchedFromHomeWidget();

  @override
  Stream<Uri?> get links => HomeWidget.widgetClicked;
}

/// The lines of "Ultime uscite": the last three Novità, "• Titolo — Artista".
String novitaText(List<NewsItem> novita) {
  if (novita.isEmpty) return 'Nessuna novità per ora.';
  return [for (final n in novita.take(3)) '• ${n.titolo} — ${n.artista}'].join('\n');
}

/// The artist of "Prossimo da recuperare": the one in Recuperando listened to most recently
/// (where the last mark is), or the first by name.
SavedArtist? currentArtist(List<SavedArtist> recuperando) {
  SavedArtist? best;
  var bestTime = -1;
  for (final a in recuperando) {
    for (final m in a.fatte.values) {
      if (m.time > bestTime) {
        bestTime = m.time;
        best = a;
      }
    }
  }
  return best ?? (recuperando.isEmpty ? null : recuperando.first);
}

/// What "Prossimo da recuperare" shows: title, detail and the artist to open.
({String titolo, String dettaglio, String id}) nextText(SavedArtist? artist, DiscoEntry? entry) {
  if (artist == null) return (titolo: 'Niente da recuperare', dettaglio: 'Aggiungi un artista a Recuperando.', id: '');
  if (entry == null || entry.state != LoadState.ok) {
    return (titolo: artist.nome, dettaglio: 'Apri CNS per caricare la discografia.', id: artist.id);
  }
  final queue = queueOf(groupReleases(entry.releases, artist.nome), artist.fatte, artist.tipiRecupero);
  final next = queue.next;
  if (next == null) return (titolo: 'Discografia finita 🎉', dettaglio: artist.nome, id: artist.id);
  return (
    titolo: next.main.title,
    dettaglio: '${artist.nome} · ${kinds[next.kind]!.label} · ${queue.done} di ${queue.total}',
    id: artist.id,
  );
}

/// Keeps the widgets up to date: when the Novità, the artists or a discography change, the
/// texts are written again (only if different) and Android redraws the widgets.
class WidgetSync {
  WidgetSync(this._bridge, this._news, this._artists, this._discos) {
    for (final source in [_news, _artists, _discos]) {
      source.addListener(_schedule);
    }
    _schedule();
  }

  final WidgetBridge _bridge;
  final NewsStore _news;
  final ArtistStore _artists;
  final DiscographyStore _discos;
  Timer? _timer;
  Map<String, String?>? _last;

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 1), _write); // many changes together: one write
  }

  Map<String, String?> texts() {
    if (_artists.state != LoadState.ok) {
      return {'novita_testo': null, 'prossimo_titolo': null, 'prossimo_dettaglio': null, 'prossimo_id': null};
    }
    final artist = currentArtist(_artists.inList(Lists.recuperando));
    final entry = artist == null ? null : _discos.ensure(artist.id);
    final next = nextText(artist, entry);
    return {
      'novita_testo': novitaText(_news.novita),
      'prossimo_titolo': next.titolo,
      'prossimo_dettaglio': next.dettaglio,
      'prossimo_id': next.id,
    };
  }

  Future<void> _write() async {
    final data = texts();
    if (mapEquals(data, _last)) return;
    _last = data;
    try {
      await _bridge.save(data);
      await _bridge.refresh();
    } catch (err) {
      debugPrint('Widget non aggiornato: $err'); // not essential
    }
  }

  void dispose() {
    _timer?.cancel();
    for (final source in [_news, _artists, _discos]) {
      source.removeListener(_schedule);
    }
  }
}
