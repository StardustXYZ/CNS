import 'package:flutter/material.dart';

import '../data/artists.dart';
import '../data/deezer.dart';
import '../theme.dart';
import 'account_pages.dart' show attempt, say;
import 'import_page.dart';
import 'search_page.dart';

/// Gives the pages the account's artists (and rebuilds them when they change).
class ArtistsScope extends InheritedNotifier<ArtistStore> {
  const ArtistsScope({super.key, required ArtistStore store, required super.child}) : super(notifier: store);

  static ArtistStore of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ArtistsScope>()!.notifier!;
}

/// Gives the pages Deezer (a fake one in the tests).
class DeezerScope extends InheritedWidget {
  const DeezerScope({super.key, required this.api, required super.child});

  final DeezerApi api;

  static DeezerApi of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<DeezerScope>()!.api;

  @override
  bool updateShouldNotify(DeezerScope oldWidget) => api != oldWidget.api;
}

/// The photo of an artist, round; a microphone while it loads or without a photo.
class ArtistPhoto extends StatelessWidget {
  const ArtistPhoto({super.key, required this.url, this.size = 48});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: CnsColors.surface2,
      child: Icon(Icons.mic, size: size * 0.5, color: CnsColors.textMuted),
    );
    return ClipOval(
      child: url.isEmpty
          ? placeholder
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(), // small in memory: lists can be long
              errorBuilder: (_, _, _) => placeholder,
              loadingBuilder: (_, child, progress) => progress == null ? child : placeholder,
            ),
    );
  }
}

/// Controllare or Recuperando: the artists in the list, with the buttons to add more.
class ArtistListPage extends StatelessWidget {
  const ArtistListPage({super.key, required this.lista});

  final String lista;

  static const _texts = {
    Lists.controllare: (
      'Gli artisti con cui sei in pari: aspetti le loro uscite nuove.',
      'Nessun artista da controllare per ora.',
      'Aggiungili con il pulsante qui sopra: ti arriverà una notifica a ogni uscita nuova.',
    ),
    Lists.recuperando: (
      "Le discografie da ascoltare dall'inizio, una uscita alla volta.",
      'Nessuna discografia da recuperare per ora.',
      "Aggiungi gli artisti di cui vuoi ascoltare tutto, dal primo album.",
    ),
  };

  @override
  Widget build(BuildContext context) {
    final store = ArtistsScope.of(context);
    final (subtitle, emptyText, emptyNote) = _texts[lista]!;
    final list = store.inList(lista);
    final archived = lista == Lists.recuperando ? store.inList(Lists.archivio) : const <SavedArtist>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(Lists.labels[lista]!, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(fontSize: 14, color: CnsColors.textMuted)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SearchPage(lista: lista))),
              icon: const Icon(Icons.add),
              label: const Text('Aggiungi artista'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImportPage(lista: lista))),
              icon: const Icon(Icons.playlist_add),
              label: const Text('Importa'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (store.state == LoadState.error)
          Text(store.error ?? 'Non riesco a leggere le tue liste.', style: const TextStyle(color: CnsColors.red))
        else if (store.state == LoadState.loading && store.all.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (list.isEmpty)
          _EmptyList(icon: lista == Lists.controllare ? Icons.headphones : Icons.album, text: emptyText, note: emptyNote)
        else
          for (final a in list) ArtistTile(artist: a),
        if (archived.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Archivio (${archived.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
              children: [for (final a in archived) ArtistTile(artist: a)],
            ),
          ),
      ],
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.icon, required this.text, required this.note});

  final IconData icon;
  final String text;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, size: 48, color: CnsColors.accent),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(note, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: CnsColors.textMuted)),
        ],
      ),
    );
  }
}

/// One artist of a list: photo, name, and the note or the fans.
class ArtistTile extends StatelessWidget {
  const ArtistTile({super.key, required this.artist});

  final SavedArtist artist;

  @override
  Widget build(BuildContext context) {
    final detail = artist.nota.isNotEmpty ? artist.nota : (artist.fan > 0 ? fansLabel(artist.fan) : '');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: CnsColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: CnsColors.border),
      ),
      child: ListTile(
        leading: ArtistPhoto(url: artist.foto),
        title: Text(artist.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: detail.isEmpty
            ? null
            : Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: CnsColors.textMuted)),
        trailing: const Icon(Icons.more_vert, color: CnsColors.textMuted),
        onTap: () => showArtistSheet(context, artist),
      ),
    );
  }
}

/// Until the artist page arrives (phase 8.4): move the artist to another list, or remove it.
Future<void> showArtistSheet(BuildContext context, SavedArtist artist) async {
  final store = ArtistsScope.of(context);
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: CnsColors.surface,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: ArtistPhoto(url: artist.foto, size: 40),
            title: Text(artist.nome, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('In ${Lists.labels[artist.lista] ?? artist.lista}'),
          ),
          const Divider(height: 1),
          for (final lista in Lists.labels.keys)
            if (lista != artist.lista)
              ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: Text('Sposta in ${Lists.labels[lista]}'),
                onTap: () => Navigator.of(sheet).pop(lista),
              ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: CnsColors.red),
            title: const Text('Togli dalle liste', style: TextStyle(color: CnsColors.red)),
            onTap: () => Navigator.of(sheet).pop('togli'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text('La pagina completa dell’artista, con la discografia, arriva nella prossima versione.',
                style: TextStyle(fontSize: 12, color: CnsColors.textMuted)),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'togli') {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Togliere ${artist.nome}?'),
        content: const Text('Sparisce dalle tue liste, anche nell’app web. La nota e il segnalibro andranno persi.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Annulla')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CnsColors.red),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Togli'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted && await attempt(context, () => store.remove(artist.id)) && context.mounted) {
      say(context, '${artist.nome} tolto dalle liste.');
    }
  } else if (await attempt(context, () => store.move(artist.id, choice)) && context.mounted) {
    say(context, '${artist.nome} spostato in ${Lists.labels[choice]}.');
  }
}
