import 'package:flutter/material.dart';

import '../data/artists.dart';
import '../data/deezer.dart' show fansLabel;
import '../data/discografia.dart';
import '../data/discography_store.dart';
import '../data/segnalibro.dart';
import '../theme.dart';
import 'account_pages.dart' show attempt, say;
import 'list_pages.dart';
import 'widgets.dart';

/// The page of one artist, as in the web app: bookmark (Recuperando) or alerts (Controllare),
/// list, note, the discography with the versions merged, and the way to remove the artist.
class ArtistPage extends StatefulWidget {
  const ArtistPage({super.key, required this.artistId, this.now});

  final String artistId;
  final int Function()? now; // the clock of the bookmark (fixed in the tests)

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  final _note = TextEditingController();
  final _noteFocus = FocusNode();
  String? _noteSaved; // the note as it is in Firebase, to save only real changes
  String _kind = ''; // the chip chosen in the discography ("" = all)
  bool? _oldestFirst;
  bool _leaving = false;

  int get _now => widget.now?.call() ?? DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _noteFocus.addListener(() {
      if (!_noteFocus.hasFocus) _saveNote(); // as the web app: when leaving the box
    });
  }

  @override
  void dispose() {
    _saveNote(quiet: true);
    _note.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  void _saveNote({bool quiet = false}) {
    final store = _store;
    final text = _note.text.trim();
    if (store == null || _noteSaved == null || text == _noteSaved) return;
    _noteSaved = text;
    store.update(widget.artistId, {'nota': text}).then((_) {
      if (!quiet && mounted) say(context, 'Nota salvata.');
    }).catchError((Object err) {
      if (!quiet && mounted) say(context, '$err');
    });
  }

  ArtistStore? _store;

  /// Saves bookmark changes; with "sposta in automatico", the last one moves the artist.
  Future<void> _saveBookmark(SavedArtist a, List<ReleaseGroup> groups, Map<String, dynamic> fields) async {
    String? info;
    final fatte = fields['fatte'];
    if (fatte is Fatte) {
      fields['fatte'] = fatteToJson(fatte);
      if (a.autoSposta && queueOf(groups, fatte, a.tipiRecupero).finished) {
        fields['lista'] = Lists.controllare;
        info = 'Discografia finita: ${a.nome} è passato in Controllare.';
      }
    }
    if (await attempt(context, () => _store!.update(a.id, fields)) && info != null && mounted) say(context, info);
  }

  Future<void> _remove(SavedArtist a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Togliere ${a.nome}?'),
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
    if (ok != true || !mounted) return;
    _leaving = true;
    _noteSaved = null; // nothing left to save
    if (await attempt(context, () => _store!.remove(a.id)) && mounted) {
      say(context, '${a.nome} tolto dalle liste.');
      Navigator.of(context).pop();
    } else {
      _leaving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = _store = ArtistsScope.of(context);
    final a = store.byId(widget.artistId);
    if (a == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(_leaving ? '' : 'Questo artista non è più nelle tue liste.',
              style: const TextStyle(color: CnsColors.textMuted)),
        ),
      );
    }
    // The note follows Firebase (the web app may change it) unless it is being written
    if (_noteSaved == null || (!_noteFocus.hasFocus && _noteSaved != a.nota)) {
      _noteSaved = a.nota;
      if (_note.text != a.nota) _note.text = a.nota;
    }
    final discos = DiscographyScope.of(context);
    final entry = discos.ensure(a.id);
    final groups = entry.state == LoadState.ok ? groupReleases(entry.releases, a.nome) : const <ReleaseGroup>[];
    final queue = a.lista == Lists.recuperando && entry.state == LoadState.ok ? queueOf(groups, a.fatte, a.tipiRecupero) : null;

    return Scaffold(
      appBar: AppBar(title: Text(a.nome, overflow: TextOverflow.ellipsis)),
      body: RefreshIndicator(
        onRefresh: () async => discos.ensure(a.id, force: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _hero(a),
            if (a.lista == Lists.recuperando) ..._bookmark(a, entry, groups, queue),
            if (a.lista == Lists.controllare) ..._alerts(a),
            const SectionTitle('Lista'),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [for (final e in Lists.labels.entries) ButtonSegment(value: e.key, label: Text(e.value))],
              selected: {a.lista},
              onSelectionChanged: (s) => attempt(context, () => store.update(a.id, {'lista': s.first})),
            ),
            const SectionTitle('Nota'),
            TextField(
              controller: _note,
              focusNode: _noteFocus,
              maxLength: 500,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Ad esempio: aspetto il nuovo album',
                border: OutlineInputBorder(),
                helperText: 'La nota si salva da sola quando esci dalla casella.',
              ),
            ),
            ..._discography(a, entry, groups, queue),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: CnsColors.red, side: const BorderSide(color: CnsColors.red)),
                onPressed: () => _remove(a),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Togli dalle liste'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(SavedArtist a) {
    return Row(
      children: [
        ArtistPhoto(url: a.foto, size: 88),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.nome, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              if (a.fan > 0) Text(fansLabel(a.fan), style: const TextStyle(color: CnsColors.textMuted)),
              if (a.link.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: OutlinedButton.icon(
                    onPressed: () => openLink(context, a.link),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Apri su Deezer'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- bookmark (Recuperando)

  List<Widget> _bookmark(SavedArtist a, DiscoEntry entry, List<ReleaseGroup> groups, BookmarkQueue? queue) {
    final fatte = a.fatte;
    final Widget body;
    if (queue == null) {
      body = Text(
        entry.state == LoadState.error
            ? 'Discografia non caricata: il segnalibro tornerà quando Deezer risponde.'
            : 'Carico la discografia da Deezer…',
        style: TextStyle(color: entry.state == LoadState.error ? CnsColors.red : CnsColors.textMuted),
      );
    } else if (queue.total == 0) {
      body = const Text('Nessuna uscita da recuperare con i tipi scelti qui sotto.',
          style: TextStyle(color: CnsColors.textMuted));
    } else if (queue.finished) {
      final undo = TextButton.icon(
        onPressed: () => _saveBookmark(a, groups, {'fatte': undoLast(fatte).$1}),
        icon: const Icon(Icons.undo, size: 18),
        label: const Text('Annulla l’ultimo'),
      );
      body = _card([
        Text(a.fineTenuta ? 'Discografia finita 🎉' : 'Hai finito la discografia di ${a.nome} 🎉',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        if (a.fineTenuta)
          const Text('Resta in Recuperando: le uscite nuove compariranno qui, in fondo alla coda.',
              style: TextStyle(fontSize: 13, color: CnsColors.textMuted))
        else ...[
          const Text('Cosa ne facciamo?', style: TextStyle(fontSize: 13, color: CnsColors.textMuted)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(
              onPressed: () => _saveBookmark(a, groups, {'lista': Lists.controllare, 'fine_tenuta': false}),
              child: const Text('Sposta in Controllare'),
            ),
            OutlinedButton(
              onPressed: () => _saveBookmark(a, groups, {'fine_tenuta': true}),
              child: const Text('Tieni qui'),
            ),
            OutlinedButton(
              onPressed: () => _saveBookmark(a, groups, {'lista': Lists.archivio, 'fine_tenuta': false}),
              child: const Text('Archivia'),
            ),
          ]),
        ],
        undo,
      ]);
    } else {
      final g = queue.next!;
      body = _card([
        const Text('Prossima da ascoltare', style: TextStyle(fontSize: 12, color: CnsColors.textMuted)),
        const SizedBox(height: 8),
        Row(children: [
          ReleaseCover(url: g.main.cover, size: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.main.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text('${kinds[g.kind]!.label} · ${dateLabel(g.date)}',
                  style: const TextStyle(fontSize: 12, color: CnsColors.textMuted)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        _linkButtons(a, g.main),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            onPressed: () => _saveBookmark(a, groups, {'fatte': mark(fatte, g.key, listened, _now)}),
            icon: const Icon(Icons.check),
            label: const Text('Ascoltato'),
          ),
          OutlinedButton(
            onPressed: () => _saveBookmark(a, groups, {'fatte': mark(fatte, g.key, skipped, _now)}),
            child: const Text('Salta'),
          ),
          if (fatte.isNotEmpty)
            TextButton.icon(
              onPressed: () => _saveBookmark(a, groups, {'fatte': undoLast(fatte).$1}),
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('Annulla l’ultimo'),
            ),
        ]),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: queue.percent / 100, minHeight: 6, borderRadius: BorderRadius.circular(3)),
        const SizedBox(height: 4),
        Text('${queue.done} di ${queue.total} (${queue.percent}%) · ascoltate ${queue.listenedCount}, '
            'saltate ${queue.skippedCount}',
            style: const TextStyle(fontSize: 12, color: CnsColors.textMuted)),
      ]);
    }
    final chosen = a.tipiRecupero;
    return [
      const SectionTitle('Segnalibro'),
      body,
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Cosa recuperare e cosa fare alla fine', style: TextStyle(fontSize: 14)),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in kinds.entries)
                FilterChip(
                  label: Text(e.value.plural),
                  selected: chosen.contains(e.key),
                  onSelected: (on) {
                    final next = on ? [...chosen, e.key] : chosen.where((k) => k != e.key).toList();
                    if (next.isEmpty) return; // at least one kind
                    _saveBookmark(a, groups, {'tipi_recupero': next});
                  },
                ),
            ]),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: a.autoSposta,
              onChanged: (v) => _saveBookmark(a, groups, {'auto_sposta': v ?? false}),
              title: const Text('Quando finisco, sposta in automatico in Controllare', style: TextStyle(fontSize: 14)),
            ),
            const Text('Per partire da dove sei arrivato, tocca «Arrivato qui» su un’uscita della discografia qui sotto.',
                style: TextStyle(fontSize: 12, color: CnsColors.textMuted)),
          ],
        ),
      ),
    ];
  }

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CnsColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: CnsColors.green),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _linkButtons(SavedArtist a, Release r) => Wrap(spacing: 8, children: [
        FilledButton.tonal(
          onPressed: () => openLink(context, spotifySearchUrl(a.nome, r.title)),
          child: const Text('Spotify'),
        ),
        OutlinedButton(onPressed: () => openLink(context, r.link), child: const Text('Deezer')),
      ]);

  // ---------------------------------------------------------------- alerts (Controllare)

  List<Widget> _alerts(SavedArtist a) {
    final chosen = a.tipiAvviso;
    return [
      const SectionTitle('Avvisi'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in kinds.entries)
          FilterChip(
            label: Text(e.value.plural),
            selected: chosen.contains(e.key),
            onSelected: (on) {
              final next = on ? [...chosen, e.key] : chosen.where((k) => k != e.key).toList();
              if (next.isEmpty) {
                say(context, 'Lascia almeno un tipo: per non ricevere avvisi, sposta l’artista in Recuperando o Archivio.');
                return;
              }
              attempt(context, () => _store!.update(a.id, {'tipi_avviso': next}));
            },
          ),
      ]),
      const SizedBox(height: 6),
      Text('Ti arriva una notifica quando ${a.nome} pubblica un’uscita di questi tipi.',
          style: const TextStyle(fontSize: 12, color: CnsColors.textMuted)),
    ];
  }

  // ---------------------------------------------------------------- discography

  List<Widget> _discography(SavedArtist a, DiscoEntry entry, List<ReleaseGroup> groups, BookmarkQueue? queue) {
    final discos = DiscographyScope.of(context);
    final out = <Widget>[const SectionTitle('Discografia')];
    if (entry.state == LoadState.idle || entry.state == LoadState.loading) {
      out.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Carico la discografia da Deezer…', style: TextStyle(color: CnsColors.textMuted)),
        ]),
      ));
      return out;
    }
    if (entry.state == LoadState.error) {
      out.addAll([
        Text('Discografia non caricata: ${entry.error}', style: const TextStyle(color: CnsColors.red)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(onPressed: () => discos.ensure(a.id, force: true), child: const Text('Riprova')),
        ),
      ]);
      return out;
    }
    final counts = countKinds(groups);
    final kind = counts.containsKey(_kind) ? _kind : '';
    final oldestFirst = _oldestFirst ?? a.lista == Lists.recuperando;
    out.add(Wrap(spacing: 6, runSpacing: 6, children: [
      ChoiceChip(
        label: Text('Tutte ${groups.length}'),
        selected: kind.isEmpty,
        onSelected: (_) => setState(() => _kind = ''),
      ),
      for (final e in kinds.entries)
        if (counts.containsKey(e.key))
          ChoiceChip(
            label: Text('${e.value.plural} ${counts[e.key]}'),
            selected: kind == e.key,
            onSelected: (_) => setState(() => _kind = e.key),
          ),
    ]));
    out.add(Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
        TextButton.icon(
          onPressed: () => setState(() => _oldestFirst = !oldestFirst),
          icon: Icon(oldestFirst ? Icons.arrow_upward : Icons.arrow_downward, size: 18),
          label: Text(oldestFirst ? 'Dalla più vecchia' : 'Dalla più recente'),
        ),
        if (entry.savedAt != null)
          Text('aggiornata il ${dateTimeLabel(entry.savedAt!)}', style: const TextStyle(fontSize: 12, color: CnsColors.textMuted)),
        if (entry.error != null)
          const Text('Deezer non risponde: è la copia salvata', style: TextStyle(fontSize: 12, color: CnsColors.yellow)),
        if (entry.loading) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
      ]),
    ));
    final rows = arrange(groups, kind: kind, oldestFirst: oldestFirst);
    if (rows.isEmpty) {
      out.add(const Text('Nessuna uscita su Deezer.', style: TextStyle(color: CnsColors.textMuted)));
    }
    for (final g in rows) {
      out.add(_releaseRow(a, g, queue, groups));
    }
    return out;
  }

  Widget _releaseRow(SavedArtist a, ReleaseGroup g, BookmarkQueue? queue, List<ReleaseGroup> groups) {
    final r = g.main;
    final inQueue = queue != null && queue.all.contains(g);
    final done = inQueue ? a.fatte[g.key] : null;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: CnsColors.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ReleaseCover(url: r.cover),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('${kinds[g.kind]!.label} · ${dateLabel(g.date)}${r.explicit ? ' · 🅴' : ''}',
                    style: const TextStyle(fontSize: 12, color: CnsColors.textMuted)),
                const SizedBox(height: 4),
                _linkButtons(a, r),
              ]),
            ),
          ]),
          if (inQueue)
            Padding(
              padding: const EdgeInsets.only(left: 68, top: 2),
              child: done != null
                  ? Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(done.state == skipped ? 'Saltato' : '✓ Ascoltato'),
                        backgroundColor: done.state == skipped ? CnsColors.surface2 : CnsColors.green.withValues(alpha: 0.3),
                      ),
                      TextButton(
                        onPressed: () => _saveBookmark(a, groups, {'fatte': unmark(a.fatte, g.key)}),
                        child: const Text('annulla'),
                      ),
                    ])
                  : TextButton(
                      onPressed: () => _saveBookmark(a, groups, {'fatte': markUpTo(queue.all, g.key, a.fatte, _now)}),
                      child: const Text('Arrivato qui'),
                    ),
            ),
          if (g.versions.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.only(left: 68),
                dense: true,
                title: Text('+${g.versions.length} ${g.versions.length == 1 ? 'versione' : 'versioni'}',
                    style: const TextStyle(fontSize: 13, color: CnsColors.accent)),
                children: [
                  for (final v in g.versions)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 68),
                      title: Text(v.title, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(dateLabel(v.date), style: const TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.open_in_new, size: 16),
                      onTap: () => openLink(context, v.link),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
