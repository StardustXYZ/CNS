import 'package:flutter/material.dart';

import '../data/artists.dart';
import '../data/discografia.dart' show dateLabel, kinds, spotifySearchUrl;
import '../data/news.dart';
import '../theme.dart';
import 'account_pages.dart' show attempt, say;
import 'artist_page.dart';
import 'list_pages.dart' show ArtistsScope;
import 'widgets.dart';

/// Gives the pages the Novità and In arrivo (and rebuilds them when they change).
class NewsScope extends InheritedNotifier<NewsStore> {
  const NewsScope({super.key, required NewsStore store, required super.child}) : super(notifier: store);

  static NewsStore of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<NewsScope>()!.notifier!;
}

/// Novità: the releases GitHub found for the artists in Controllare, the newest first, with
/// the announced ones ("In arrivo") on top, as the web app.
class NovitaPage extends StatelessWidget {
  const NovitaPage({super.key});

  Future<void> _clear(BuildContext context, NewsStore news) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Svuotare le Novità?'),
        content: Text('Cancello tutte le ${news.novita.length} Novità, anche nell’app web. '
            'Le uscite restano nella discografia degli artisti.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Annulla')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CnsColors.red),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Svuota'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) await attempt(context, news.clear);
  }

  @override
  Widget build(BuildContext context) {
    final news = NewsScope.of(context);
    final coming = news.comingSoon();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Text('Novità', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        const Text('Le uscite nuove degli artisti in Controllare, dalla più recente.',
            style: TextStyle(fontSize: 14, color: CnsColors.textMuted)),
        if (coming.isNotEmpty) ...[
          const SectionTitle('In arrivo'),
          for (final n in coming) AnnouncementTile(item: n, today: news.today),
          const SectionTitle('Uscite'),
        ] else
          const SizedBox(height: 12),
        if (news.state == LoadState.error)
          Text(news.error ?? 'Non riesco a leggere le Novità.', style: const TextStyle(color: CnsColors.red))
        else if (news.state == LoadState.loading && news.novita.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (news.novita.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32, horizontal: 8),
            child: Column(children: [
              Icon(Icons.notifications_none, size: 48, color: CnsColors.accent),
              SizedBox(height: 12),
              Text('Nessuna novità per ora.', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              SizedBox(height: 6),
              Text('Quando un artista di Controllare pubblica qualcosa, la trovi qui.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: CnsColors.textMuted)),
            ]),
          )
        else ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('Scorri un’uscita verso sinistra per toglierla.',
                style: TextStyle(fontSize: 12, color: CnsColors.textMuted)),
          ),
          for (final n in news.novita)
            Dismissible(
              key: ValueKey('novita-${n.id}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: CnsColors.red.withValues(alpha: 0.6),
                child: const Icon(Icons.delete_outline),
              ),
              onDismissed: (_) => attempt(context, () => news.remove(n.id)),
              child: NovitaTile(item: n),
            ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: CnsColors.red, side: const BorderSide(color: CnsColors.red)),
              onPressed: () => _clear(context, news),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Svuota le Novità'),
            ),
          ),
        ],
      ],
    );
  }
}

/// Opens the artist's page, if the artist is still in the lists.
void _openArtist(BuildContext context, String artistId, String name) {
  if (ArtistsScope.of(context).byId(artistId) == null) {
    say(context, '$name non è più nelle tue liste.');
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArtistPage(artistId: artistId)));
}

String _kindLabel(String tipo) => kinds[tipo]?.label ?? 'Uscita';

/// One Novità: cover, title, artist, kind and date, when it was notified, Spotify and Deezer.
class NovitaTile extends StatelessWidget {
  const NovitaTile({super.key, required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final n = item;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: CnsColors.border))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ReleaseCover(url: n.copertina),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n.titolo, style: const TextStyle(fontWeight: FontWeight.w600)),
            InkWell(
              onTap: () => _openArtist(context, n.artistaId, n.artista),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: n.artista, style: const TextStyle(color: CnsColors.accent)),
                TextSpan(text: ' · ${_kindLabel(n.tipo)} · ${dateLabel(n.data)}'),
              ]), style: const TextStyle(fontSize: 12, color: CnsColors.textMuted)),
            ),
            if (n.notificata != null)
              Text('notificata il ${dateTimeLabel(n.notificata!)}',
                  style: const TextStyle(fontSize: 11, color: CnsColors.textMuted)),
            const SizedBox(height: 4),
            Wrap(spacing: 8, children: [
              FilledButton.tonal(
                onPressed: () => openLink(context, n.spotify.isNotEmpty ? n.spotify : spotifySearchUrl(n.artista, n.titolo)),
                child: const Text('Spotify'),
              ),
              if (n.link.isNotEmpty) OutlinedButton(onPressed: () => openLink(context, n.link), child: const Text('Deezer')),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// One announced release: when it comes out, Spotify on the day, Apple Music (iTunes pre-order).
class AnnouncementTile extends StatelessWidget {
  const AnnouncementTile({super.key, required this.item, required this.today, this.showArtist = true});

  final NewsItem item;
  final DateTime today;
  final bool showArtist;

  @override
  Widget build(BuildContext context) {
    final n = item;
    final isToday = n.data == isoDay(today);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: CnsColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isToday ? CnsColors.green : CnsColors.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        n.copertina.isEmpty
            ? Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: CnsColors.surface2, borderRadius: BorderRadius.circular(6)),
                child: const Icon(Icons.event, color: CnsColors.textMuted),
              )
            : ReleaseCover(url: n.copertina),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n.titolo, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (showArtist)
              InkWell(
                onTap: () => _openArtist(context, n.artistaId, n.artista),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: n.artista, style: const TextStyle(color: CnsColors.accent)),
                  TextSpan(text: ' · ${_kindLabel(n.tipo)}'),
                ]), style: const TextStyle(fontSize: 12, color: CnsColors.textMuted)),
              )
            else
              Text(_kindLabel(n.tipo), style: const TextStyle(fontSize: 12, color: CnsColors.textMuted)),
            Text(daysLeftLabel(n.data, today),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isToday ? CnsColors.accent : CnsColors.yellow)),
            const SizedBox(height: 4),
            Wrap(spacing: 8, children: [
              if (isToday)
                FilledButton.tonal(
                  onPressed: () =>
                      openLink(context, n.spotify.isNotEmpty ? n.spotify : spotifySearchUrl(n.artista, n.titolo)),
                  child: const Text('Spotify'),
                ),
              if (n.link.isNotEmpty)
                OutlinedButton(onPressed: () => openLink(context, n.link), child: const Text('Apple Music')),
            ]),
          ]),
        ),
      ]),
    );
  }
}
