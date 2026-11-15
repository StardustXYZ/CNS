import 'package:flutter/material.dart';

import '../data/artists.dart';
import '../data/deezer.dart';
import '../theme.dart';
import 'account_pages.dart' show attempt, say;
import 'list_pages.dart' show ArtistPhoto, ArtistsScope;
import 'widgets.dart';

/// "Ti potrebbero piacere": the artists Deezer considers similar, with the + to add them.
/// The ones already in a list are left out.
class RelatedArtists extends StatelessWidget {
  const RelatedArtists({super.key, required this.artistId});

  final String artistId;

  @override
  Widget build(BuildContext context) {
    final store = ArtistsScope.of(context);
    return FutureBuilder<List<DeezerArtist>>(
      future: DiscographyScope.of(context).related(artistId),
      builder: (context, snap) {
        if (snap.hasError) return const SizedBox(); // not essential: the page works without it
        final found = [for (final a in snap.data ?? const <DeezerArtist>[]) if (store.byId(a.id) == null) a];
        if (snap.hasData && found.isEmpty) return const SizedBox();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Ti potrebbero piacere'),
            SizedBox(
              height: 150,
              child: !snap.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: found.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, i) => _Similar(artist: found[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Similar extends StatelessWidget {
  const _Similar({required this.artist});

  final DeezerArtist artist;

  @override
  Widget build(BuildContext context) {
    final store = ArtistsScope.of(context);
    return SizedBox(
      width: 92,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ArtistPhoto(url: artist.picture, size: 76),
              Positioned(
                right: -8,
                bottom: -6,
                child: PopupMenuButton<String>(
                  tooltip: 'Aggiungi ${artist.name}',
                  onSelected: (lista) async {
                    if (await attempt(context, () => store.add(artist, lista)) && context.mounted) {
                      say(context, '${artist.name} aggiunto a ${Lists.labels[lista]}.');
                    }
                  },
                  itemBuilder: (_) => [
                    for (final lista in [Lists.controllare, Lists.recuperando])
                      PopupMenuItem(value: lista, child: Text('Aggiungi a ${Lists.labels[lista]}')),
                  ],
                  child: const CircleAvatar(
                    radius: 16,
                    backgroundColor: CnsColors.green,
                    child: Icon(Icons.add, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(artist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          if (artist.fans > 0)
            Text(fansLabel(artist.fans),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: CnsColors.textMuted)),
        ],
      ),
    );
  }
}
