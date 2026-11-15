import 'package:flutter/material.dart';

import '../data/backup.dart';
import '../data/copia.dart' show BackupError, ParsedBackup;
import '../theme.dart';
import 'account_pages.dart';

/// Gives the Impostazioni page the backup ("Salva la copia", "Ripristina").
class BackupScope extends InheritedWidget {
  const BackupScope({super.key, required this.service, required super.child});

  final BackupService service;

  static BackupService of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<BackupScope>()!.service;

  @override
  bool updateShouldNotify(BackupScope oldWidget) => service != oldWidget.service;
}

/// Impostazioni: the account (with the allow list for the administrator) and the backup copy;
/// the notifications on the phone arrive in phase 8.7.
class ImpostazioniPage extends StatelessWidget {
  const ImpostazioniPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        AccountCard(),
        SettingsCard(
          title: 'Notifiche',
          child: Text(
            'Le notifiche sul telefono arrivano in una delle prossime versioni. '
            'Intanto restano quelle di ntfy, che scegli nell’app web.',
          ),
        ),
        BackupCard(),
      ],
    );
  }
}

/// A box of the Impostazioni page, as the cards of the web app.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CnsColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CnsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 13, color: CnsColors.textMuted, height: 1.4),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// "Account": who is signed in, the user code, the allow list for the administrator, and
/// the way out.
class AccountCard extends StatelessWidget {
  const AccountCard({super.key});

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.of(context);
    final user = account.user;
    if (user == null) return const SizedBox();
    final name = user.name ?? '';
    return SettingsCard(
      title: 'Account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            name.isNotEmpty ? '$name · ${user.email}' : user.email,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: CnsColors.text),
          ),
          const SizedBox(height: 4),
          Text(user.google ? 'Accesso con Google' : 'Accesso con email e password'),
          const Text('✓ Sei tra le persone ammesse.', style: TextStyle(color: CnsColors.accent)),
          const SizedBox(height: 4),
          UserCode(uid: user.uid),
          if (account.isAdmin) ...[
            const SizedBox(height: 4),
            FilledButton.tonalIcon(
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => AllowListPage(account: account))),
              icon: const Icon(Icons.group_add),
              label: Text('Persone ammesse (${account.allowed!.length})'),
            ),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: account.busy ? null : () => confirmSignOut(context, account),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Esci dall’account'),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Copia di sicurezza": a file with the lists, notes, bookmarks, alerts and the Novità, in the
/// same format as the web app (a copy made on one is restored on the other).
class BackupCard extends StatefulWidget {
  const BackupCard({super.key});

  @override
  State<BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<BackupCard> {
  bool _busy = false;
  String? _message;
  bool _ok = true;

  /// Runs "Salva" or "Ripristina" and shows how it went.
  Future<void> _run(Future<String?> Function(BackupService service) action) async {
    final service = BackupScope.of(context);
    try {
      final message = await action(service);
      if (mounted && message != null) setState(() => _show(message, ok: true));
    } on BackupError catch (err) {
      if (mounted) setState(() => _show('Copia non ripristinata: ${err.message}.', ok: false));
    } catch (err) {
      if (mounted) setState(() => _show('$err', ok: false));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The bar under the buttons, only while the phone works (not while a window asks something).
  Future<T> _working<T>(Future<T> Function() work) async {
    setState(() => _busy = true);
    try {
      return await work();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message, {required bool ok}) {
    _message = message;
    _ok = ok;
  }

  Future<String?> _save(BackupService service) async {
    final count = await _working(service.save);
    return count == null ? null : 'Copia salvata: $count artisti ✓';
  }

  Future<String?> _restore(BackupService service) async {
    final backup = await service.choose();
    if (backup == null || !mounted) return null;
    if (!await _confirm(backup)) return null;
    await _working(() => service.restore(backup));
    return 'Ripristinati ${backup.artists.length} artisti ✓';
  }

  Future<bool> _confirm(ParsedBackup backup) async {
    final skipped = backup.skipped > 0 ? ' (${backup.skipped} non validi verranno saltati)' : '';
    return await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Ripristinare la copia?'),
            content: Text(
              'Ripristino ${backup.artists.length} artisti dalla copia$skipped. '
              'Quelli con lo stesso codice verranno sostituiti, gli altri restano.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Annulla')),
              FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Ripristina')),
            ],
          ),
        ) ==
        true;
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: 'Copia di sicurezza',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Un file con le tue liste, le note, i segnalibri, le canzoni spuntate, gli avvisi e lo storico '
            'delle Novità. Tienilo sul telefono o sul PC: con «Ripristina» torna tutto com’era. '
            'È lo stesso file dell’app web: una copia fatta lì si ripristina qui, e viceversa.',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _run(_save),
                icon: const Icon(Icons.save_alt),
                label: const Text('Salva la copia'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(_restore),
                icon: const Icon(Icons.restore),
                label: const Text('Ripristina da una copia'),
              ),
            ],
          ),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_message!, style: TextStyle(color: _ok ? CnsColors.accent : CnsColors.red)),
            ),
        ],
      ),
    );
  }
}
