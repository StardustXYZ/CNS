import 'package:flutter/material.dart';

import '../data/artists.dart';
import '../data/discografia.dart';
import '../data/segnalibro.dart';
import '../theme.dart';
import 'account_pages.dart' show attempt;
import 'list_pages.dart' show ArtistsScope;
import 'widgets.dart';

/// The songs of one release, with their length. In Recuperando each song can be ticked on its
/// own, in any order: when they are all ticked, the release counts as listened.
class TracksPage extends StatelessWidget {
  const TracksPage({super.key, required this.artistId, required this.group, required this.tickable, this.now});

  final String artistId;
  final ReleaseGroup group;
  final bool tickable; // the release is in the artist's Recuperando queue
  final int Function()? now;

  @override
  Widget build(BuildContext context) {
    final store = ArtistsScope.of(context);
    final artist = store.byId(artistId);
    final discos = DiscographyScope.of(context);
    final r = group.main;
    return Scaffold(
      appBar: AppBar(title: Text(r.title, overflow: TextOverflow.ellipsis)),
      body: FutureBuilder<List<Track>>(
        future: discos.tracks(r.id),
        builder: (context, snap) {
          final header = <Widget>[
            Row(children: [
              ReleaseCover(url: r.cover, size: 96),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  if (artist != null) Text(artist.nome, style: const TextStyle(color: CnsColors.textMuted)),
                  Text('${kinds[group.kind]!.label} · ${dateLabel(group.date)}${r.explicit ? ' · 🅴' : ''}',
                      style: const TextStyle(fontSize: 12, color: CnsColors.textMuted)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: [
                    FilledButton.tonal(
                      onPressed: () => openLink(context, spotifySearchUrl(artist?.nome ?? '', r.title)),
                      child: const Text('Spotify'),
                    ),
                    OutlinedButton(onPressed: () => openLink(context, r.link), child: const Text('Deezer')),
                  ]),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
          ];
          if (snap.hasError) {
            return ListView(padding: const EdgeInsets.all(16), children: [
              ...header,
              Text('Canzoni non caricate: ${snap.error}', style: const TextStyle(color: CnsColors.red)),
            ]);
          }
          if (!snap.hasData) {
            return ListView(padding: const EdgeInsets.all(16), children: [
              ...header,
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            ]);
          }
          final tracks = snap.data!;
          final keys = trackKeys(tracks);
          final ticks = artist?.canzoni[group.key] ?? const <String, int>{};
          final done = artist?.fatte[group.key];
          final total = tracks.fold<int>(0, (sum, t) => sum + t.duration);
          final disks = tracks.map((t) => t.disk).toSet();
          final ticked = keys.where(ticks.containsKey).length;
          final rows = <Widget>[
            Text(
              [
                '${tracks.length} ${tracks.length == 1 ? 'canzone' : 'canzoni'}',
                if (total > 0) totalLabel(total),
                if (tickable && tracks.isNotEmpty) 'ascoltate $ticked',
              ].join(' · '),
              style: const TextStyle(fontSize: 13, color: CnsColors.textMuted),
            ),
            if (tickable && done?.state == listened && ticked < tracks.length)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Segnata come ascoltata nel segnalibro.', style: TextStyle(fontSize: 12, color: CnsColors.accent)),
              ),
            if (tickable)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Spunta le canzoni che hai ascoltato, nell’ordine che vuoi: con tutte spuntate, '
                    'l’uscita conta come ascoltata.',
                    style: TextStyle(fontSize: 12, color: CnsColors.textMuted)),
              ),
            const SizedBox(height: 8),
          ];
          if (tracks.isEmpty) {
            rows.add(const Text('Deezer non ha la lista delle canzoni di questa uscita.',
                style: TextStyle(color: CnsColors.textMuted)));
          }
          int? lastDisk;
          for (var i = 0; i < tracks.length; i++) {
            final t = tracks[i];
            if (disks.length > 1 && t.disk != lastDisk) {
              rows.add(Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text('Disco ${t.disk}', style: const TextStyle(fontWeight: FontWeight.w700, color: CnsColors.accent)),
              ));
              lastDisk = t.disk;
            }
            final number = Text('${t.position > 0 ? t.position : i + 1}',
                style: const TextStyle(color: CnsColors.textMuted, fontFeatures: [FontFeature.tabularFigures()]));
            final title = Text('${t.title}${t.explicit ? ' 🅴' : ''}');
            final length = Text(durationLabel(t.duration), style: const TextStyle(fontSize: 12, color: CnsColors.textMuted));
            if (tickable && artist != null) {
              rows.add(CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: ticks.containsKey(keys[i]),
                title: Row(children: [SizedBox(width: 26, child: number), Expanded(child: title)]),
                secondary: length,
                onChanged: (_) {
                  final (canzoni, fatte) = toggleSong(artist.canzoni, artist.fatte, group.key, keys[i], keys,
                      now?.call() ?? DateTime.now().millisecondsSinceEpoch);
                  attempt(context, () => store.update(artist.id, {
                        'canzoni': canzoniToJson(canzoni),
                        'fatte': fatteToJson(fatte),
                      }));
                },
              ));
            } else {
              rows.add(ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: SizedBox(width: 26, child: Center(child: number)),
                title: title,
                trailing: length,
              ));
            }
          }
          return ListView(padding: const EdgeInsets.all(16), children: [...header, ...rows]);
        },
      ),
    );
  }
}

/// "5/12 canzoni" for a release with some songs ticked (null when none is).
String? songsProgress(SavedArtist artist, ReleaseGroup group) {
  final ticks = artist.canzoni[group.key];
  return ticks == null || ticks.isEmpty ? null : '${ticks.length} ${ticks.length == 1 ? 'canzone' : 'canzoni'} spuntate';
}
