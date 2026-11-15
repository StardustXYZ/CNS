import 'dart:math';

import 'package:flutter/material.dart';

import '../data/artists.dart';
import '../data/discografia.dart';
import '../data/discography_store.dart';
import '../data/segnalibro.dart';
import '../theme.dart';
import 'account_pages.dart' show attempt, say;
import 'artist_page.dart';
import 'list_pages.dart' show ArtistsScope;
import 'widgets.dart';

/// One release still to listen to, of one artist in Recuperando.
class Pick {
  const Pick(this.artist, this.group);

  final SavedArtist artist;
  final ReleaseGroup group;
}

/// Every release not done yet in the queues of the artists in Recuperando (only the ones
/// whose discography is already on the phone); with [onlyAlbums], albums and EPs only.
List<Pick> candidates(List<SavedArtist> recuperando, DiscographyStore discos, {bool onlyAlbums = false}) => [
      for (final a in recuperando)
        if (discos.entry(a.id).state == LoadState.ok)
          for (final g in queueOf(groupReleases(discos.entry(a.id).releases, a.nome), a.fatte, a.tipiRecupero).pending)
            if (!onlyAlbums || g.kind == 'album' || g.kind == 'ep') Pick(a, g),
    ];

/// "Cosa ascolto adesso?": a release chosen at random among the ones still to listen to.
Future<void> showRandomPick(BuildContext context, {Random? random, int Function()? now}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: CnsColors.surface,
      showDragHandle: true,
      builder: (_) => _RandomPick(random: random ?? Random(), now: now),
    );

class _RandomPick extends StatefulWidget {
  const _RandomPick({required this.random, this.now});

  final Random random;
  final int Function()? now;

  @override
  State<_RandomPick> createState() => _RandomPickState();
}

class _RandomPickState extends State<_RandomPick> {
  bool _onlyAlbums = false;
  Pick? _pick;
  String? _lastKey;

  void _choose(List<Pick> all) {
    // Another one, not the same as before (when there is a choice)
    final others = all.length > 1 ? all.where((p) => '${p.artist.id}/${p.group.key}' != _lastKey).toList() : all;
    final pick = others.isEmpty ? null : others[widget.random.nextInt(others.length)];
    _pick = pick;
    _lastKey = pick == null ? null : '${pick.artist.id}/${pick.group.key}';
  }

  @override
  Widget build(BuildContext context) {
    final store = ArtistsScope.of(context);
    final discos = DiscographyScope.of(context);
    final recuperando = store.inList(Lists.recuperando);
    for (final a in recuperando) {
      discos.ensure(a.id); // the discographies not on the phone yet arrive meanwhile
    }
    final all = candidates(recuperando, discos, onlyAlbums: _onlyAlbums);
    // The pick is kept until "Un'altra"; if it was just marked, or the filter excludes it, a new one
    final current = _pick;
    final stillThere = current != null &&
        all.any((p) => p.artist.id == current.artist.id && p.group.key == current.group.key);
    if (!stillThere) _choose(all);
    final pick = _pick;
    final loading = recuperando.any((a) => discos.entry(a.id).state != LoadState.ok && discos.entry(a.id).state != LoadState.error);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Cosa ascolto adesso?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _onlyAlbums,
              onChanged: (v) => setState(() {
                _onlyAlbums = v;
                _pick = null;
              }),
              title: const Text('Solo album ed EP', style: TextStyle(fontSize: 14)),
            ),
            if (pick == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  loading
                      ? 'Carico le discografie da Deezer…'
                      : recuperando.isEmpty
                          ? 'Nessun artista in Recuperando.'
                          : 'Hai ascoltato tutto quello che c’è da recuperare 🎉',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: CnsColors.textMuted),
                ),
              )
            else ...[
              const SizedBox(height: 8),
              Center(child: ReleaseCover(url: pick.group.main.cover, size: 160)),
              const SizedBox(height: 12),
              Text(pick.group.main.title,
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text(pick.artist.nome, textAlign: TextAlign.center, style: const TextStyle(color: CnsColors.accent)),
              Text('${kinds[pick.group.kind]!.label} · ${dateLabel(pick.group.date)}',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: CnsColors.textMuted)),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => openLink(context, spotifySearchUrl(pick.artist.nome, pick.group.main.title)),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Apri su Spotify'),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final now = widget.now?.call() ?? DateTime.now().millisecondsSinceEpoch;
                      final fatte = mark(pick.artist.fatte, pick.group.key, listened, now);
                      if (await attempt(context, () => store.update(pick.artist.id, {'fatte': fatteToJson(fatte)})) &&
                          context.mounted) {
                        say(context, '${pick.group.main.title} segnata come ascoltata.');
                      }
                    },
                    icon: const Icon(Icons.check),
                    label: const Text('Ascoltato'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: all.length > 1 ? () => setState(() => _choose(all)) : null,
                    icon: const Icon(Icons.shuffle),
                    label: const Text('Un’altra'),
                  ),
                ),
              ]),
              TextButton(
                onPressed: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  navigator.push(MaterialPageRoute(builder: (_) => ArtistPage(artistId: pick.artist.id)));
                },
                child: Text('Apri ${pick.artist.nome}'),
              ),
              Text('Scelta tra ${all.length} ${all.length == 1 ? 'uscita' : 'uscite'} da ascoltare.',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: CnsColors.textMuted)),
            ],
          ],
        ),
      ),
    );
  }
}
