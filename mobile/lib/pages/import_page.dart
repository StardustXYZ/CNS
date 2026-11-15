import 'package:flutter/material.dart';

import '../data/artists.dart';
import '../data/deezer.dart';
import '../data/importer.dart';
import '../theme.dart';
import 'account_pages.dart' show say;
import 'list_pages.dart';

/// Import many artists at once: the favourite artists of a public Deezer profile, or a list
/// of names. Before saving, a review: what was found, with the wrong ones to uncheck.
class ImportPage extends StatefulWidget {
  const ImportPage({super.key, required this.lista});

  final String lista;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

enum _Source { profile, names }

class _ImportPageState extends State<ImportPage> {
  final _input = TextEditingController();
  _Source _source = _Source.profile;
  late String _destination = widget.lista;
  bool _searching = false;
  bool _saving = false;
  bool _stopped = false;
  (int, int)? _progress;
  String? _problem;
  List<ImportCandidate>? _found;

  @override
  void dispose() {
    _stopped = true; // a search still running stops at the next name
    _input.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final deezer = DeezerScope.of(context);
    final text = _input.text.trim();
    FocusScope.of(context).unfocus();
    if (text.isEmpty) {
      setState(() => _problem = _source == _Source.profile ? 'Incolla il link del profilo.' : 'Scrivi almeno un nome.');
      return;
    }
    final names = _source == _Source.names ? parseNames(text) : const <String>[];
    if (_source == _Source.names && names.length > maxImportNames) {
      setState(() => _problem = 'Al massimo $maxImportNames nomi per volta: ne hai scritti ${names.length}.');
      return;
    }
    setState(() {
      _searching = true;
      _problem = null;
      _found = null;
      _progress = null;
    });
    try {
      final found = _source == _Source.profile
          ? await findFromProfile(deezer, text)
          : await findByNames(deezer, names,
              onProgress: (done, total) {
                if (mounted) setState(() => _progress = (done, total));
              },
              cancelled: () => _stopped);
      if (mounted) setState(() => _found = found);
    } catch (err) {
      if (mounted) setState(() => _problem = '$err');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _save() async {
    final store = ArtistsScope.of(context);
    final chosen = [for (final c in _found ?? const <ImportCandidate>[]) if (c.selected && c.artist != null) c.artist!];
    setState(() => _saving = true);
    try {
      final added = await store.addMany(chosen, _destination);
      if (!mounted) return;
      final label = Lists.labels[_destination];
      say(context, added == 0 ? 'Nessun artista nuovo: erano già tutti nelle tue liste.' : 'Aggiunti $added artisti a $label.');
      Navigator.of(context).pop();
    } catch (err) {
      if (mounted) setState(() => _problem = '$err');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ArtistsScope.of(context);
    final found = _found;
    return Scaffold(
      appBar: AppBar(title: const Text('Importa artisti')),
      body: found == null ? _form() : _review(store, found),
    );
  }

  Widget _form() {
    final profile = _source == _Source.profile;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<_Source>(
          segments: const [
            ButtonSegment(value: _Source.profile, label: Text('Profilo Deezer'), icon: Icon(Icons.person)),
            ButtonSegment(value: _Source.names, label: Text('Elenco di nomi'), icon: Icon(Icons.list)),
          ],
          selected: {_source},
          onSelectionChanged: _searching
              ? null
              : (s) => setState(() {
                    _source = s.first;
                    _problem = null;
                    _input.clear();
                  }),
        ),
        const SizedBox(height: 14),
        Text(
          profile
              ? 'Incolla il link di un profilo Deezer pubblico: prendo i suoi artisti preferiti. '
                  'Nell’app Deezer: Profilo › Condividi › Copia link.'
              : 'Scrivi o incolla i nomi, uno per riga. Li cerco su Deezer uno alla volta.',
          style: const TextStyle(fontSize: 13, color: CnsColors.textMuted, height: 1.4),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _input,
          enabled: !_searching,
          autocorrect: false,
          keyboardType: profile ? TextInputType.url : TextInputType.multiline,
          minLines: profile ? 1 : 6,
          maxLines: profile ? 1 : 12,
          decoration: InputDecoration(
            labelText: profile ? 'Link del profilo' : 'Nomi degli artisti',
            hintText: profile ? 'https://www.deezer.com/it/profile/…' : 'Ava Max\nArctic Monkeys\nK/DA',
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_problem!, style: const TextStyle(color: CnsColors.red)),
          ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _searching ? null : _search,
          icon: const Icon(Icons.search),
          label: Text(_searching ? 'Cerco…' : 'Cerca su Deezer'),
        ),
        if (_searching && _progress != null) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _progress!.$1 / _progress!.$2),
          const SizedBox(height: 4),
          Text('${_progress!.$1} di ${_progress!.$2}', style: const TextStyle(fontSize: 12, color: CnsColors.textMuted)),
        ] else if (_searching)
          const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
      ],
    );
  }

  Widget _review(ArtistStore store, List<ImportCandidate> found) {
    final usable = [for (final c in found) if (c.artist != null && store.byId(c.artist!.id) == null) c];
    final already = found.where((c) => c.artist != null && store.byId(c.artist!.id) != null).length;
    final missing = found.where((c) => c.artist == null).toList();
    final chosen = usable.where((c) => c.selected).length;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            children: [
              Text(
                [
                  'Trovati ${usable.length} artisti nuovi.',
                  if (already > 0) '$already sono già nelle tue liste e li salto.',
                  if (missing.isNotEmpty) '${missing.length} non trovati.',
                ].join(' '),
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 4),
              const Text('Togli la spunta a quelli sbagliati. Quelli con un nome diverso da come l’hai scritto '
                  'sono senza spunta: controllali.',
                  style: TextStyle(fontSize: 12, color: CnsColors.textMuted, height: 1.35)),
              if (usable.length > 1)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() {
                      final all = chosen < usable.length;
                      for (final c in usable) {
                        c.selected = all;
                      }
                    }),
                    child: Text(chosen < usable.length ? 'Seleziona tutti' : 'Togli tutte le spunte'),
                  ),
                ),
              for (final c in usable)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: c.selected,
                  onChanged: (v) => setState(() => c.selected = v ?? false),
                  secondary: ArtistPhoto(url: c.artist!.picture, size: 40),
                  title: Text(c.artist!.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    c.exact || c.query.isEmpty
                        ? fansLabel(c.artist!.fans)
                        : 'Hai scritto “${c.query}” · ${fansLabel(c.artist!.fans)}',
                    style: TextStyle(fontSize: 12, color: c.exact ? CnsColors.textMuted : CnsColors.yellow),
                  ),
                ),
              if (missing.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Non trovati: ${missing.map((c) => c.query).join(', ')}',
                    style: const TextStyle(fontSize: 12, color: CnsColors.textMuted)),
              ],
              if (_problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_problem!, style: const TextStyle(color: CnsColors.red)),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(
              color: CnsColors.surface,
              border: Border(top: BorderSide(color: CnsColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: Lists.controllare, label: Text('In Controllare')),
                    ButtonSegment(value: Lists.recuperando, label: Text('In Recuperando')),
                  ],
                  selected: {_destination},
                  onSelectionChanged: _saving ? null : (s) => setState(() => _destination = s.first),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: _saving ? null : () => setState(() => _found = null),
                      child: const Text('Indietro'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving || chosen == 0 ? null : _save,
                        child: Text(_saving ? 'Salvo…' : 'Aggiungi $chosen artisti'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
