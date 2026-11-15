import 'dart:async';

import 'package:flutter/material.dart';

import '../data/artists.dart';
import '../data/deezer.dart';
import '../theme.dart';
import 'account_pages.dart' show attempt;
import 'list_pages.dart';

/// "Aggiungi a Controllare / Recuperando": search Deezer by name, or paste an artist's link.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.lista});

  final String lista;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const _delay = Duration(milliseconds: 350); // wait for a pause in typing before asking Deezer

  final _query = TextEditingController();
  Timer? _timer;
  int _seq = 0; // a slower older answer must not replace a newer one
  LoadState _state = LoadState.idle;
  List<DeezerArtist> _results = const [];
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _timer?.cancel();
    if (text.trim().isEmpty) {
      setState(() {
        _state = LoadState.idle;
        _results = const [];
      });
      return;
    }
    setState(() => _state = LoadState.loading);
    _timer = Timer(_delay, () => _search(text.trim()));
  }

  Future<void> _search(String query) async {
    final seq = ++_seq;
    final deezer = DeezerScope.of(context);
    try {
      var text = query;
      if (isShortLink(text)) text = await deezer.resolveLink(text);
      final id = artistIdFromLink(text);
      final results = id != null ? [await deezer.artist(id)] : await deezer.searchArtists(query);
      if (!mounted || seq != _seq) return;
      setState(() {
        _state = LoadState.ok;
        _results = results;
        _error = null;
      });
    } catch (err) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _state = LoadState.error;
        _results = const [];
        _error = 'Ricerca non riuscita: $err';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ArtistsScope.of(context);
    final label = Lists.labels[widget.lista]!;
    return Scaffold(
      appBar: AppBar(title: Text('Aggiungi a $label')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _query,
            autofocus: true,
            autocorrect: false,
            textInputAction: TextInputAction.search,
            onChanged: _changed,
            onSubmitted: (text) {
              _timer?.cancel();
              if (text.trim().isNotEmpty) _search(text.trim());
            },
            decoration: InputDecoration(
              labelText: "Nome dell'artista o link di Deezer",
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Cancella',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _query.clear();
                        _changed('');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 12),
          switch (_state) {
            LoadState.idle => const Text('Ad esempio: Ava Max, Arctic Monkeys, K/DA.',
                style: TextStyle(fontSize: 13, color: CnsColors.textMuted)),
            LoadState.loading => const Text('Cerco su Deezer…', style: TextStyle(fontSize: 13, color: CnsColors.textMuted)),
            LoadState.error => Text(_error ?? 'Ricerca non riuscita.', style: const TextStyle(color: CnsColors.red)),
            LoadState.ok when _results.isEmpty =>
              const Text('Nessun artista trovato.', style: TextStyle(fontSize: 13, color: CnsColors.textMuted)),
            LoadState.ok => Column(
                children: [for (final a in _results) _ResultTile(artist: a, lista: widget.lista, saved: store.byId(a.id))],
              ),
          },
        ],
      ),
    );
  }
}

/// One search result: "Aggiungi", "Sposta qui" if it is in another list, or "Già in lista".
class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.artist, required this.lista, required this.saved});

  final DeezerArtist artist;
  final String lista;
  final SavedArtist? saved;

  @override
  Widget build(BuildContext context) {
    final store = ArtistsScope.of(context);
    final where = saved != null && saved!.lista != lista ? ' · in ${Lists.labels[saved!.lista] ?? saved!.lista}' : '';
    final Widget action;
    if (saved?.lista == lista) {
      action = const Chip(label: Text('Già in lista ✓'), visualDensity: VisualDensity.compact);
    } else if (saved != null) {
      action = OutlinedButton(onPressed: () => attempt(context, () => store.add(artist, lista)), child: const Text('Sposta qui'));
    } else {
      action = FilledButton(onPressed: () => attempt(context, () => store.add(artist, lista)), child: const Text('Aggiungi'));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          ArtistPhoto(url: artist.picture),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(artist.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('${fansLabel(artist.fans)} · ${artist.albums} uscite$where',
                    style: const TextStyle(fontSize: 12, color: CnsColors.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          action,
        ],
      ),
    );
  }
}
