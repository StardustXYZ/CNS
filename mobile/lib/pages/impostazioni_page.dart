import 'package:flutter/material.dart';

import '../data/account.dart' show AccountStore;
import '../data/backup.dart';
import '../data/copia.dart' show BackupError, ParsedBackup;
import '../data/notifications.dart';
import '../theme.dart';
import 'account_pages.dart';
import 'app_info.dart';

/// Gives the pages the notifications of this phone (null without Firebase, as in some tests).
class NotificationScope extends InheritedNotifier<NotificationStore> {
  const NotificationScope({super.key, required NotificationStore? store, required super.child})
    : super(notifier: store);

  static NotificationStore? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NotificationScope>()?.notifier;
}

/// Gives the Impostazioni page the backup ("Salva la copia", "Ripristina").
class BackupScope extends InheritedWidget {
  const BackupScope({super.key, required this.service, required super.child});

  final BackupService service;

  static BackupService of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<BackupScope>()!.service;

  @override
  bool updateShouldNotify(BackupScope oldWidget) => service != oldWidget.service;
}

/// Impostazioni: the account (with the allow list for the administrator), the notifications on
/// this phone and the backup copy.
/// The version of the app shown in Impostazioni (read at start from the APK; "" in the tests).
String appVersion = '';

class ImpostazioniPage extends StatelessWidget {
  const ImpostazioniPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const AccountCard(),
        const NotificationsCard(),
        const BackupCard(),
        AppInfoCard(version: appVersion),
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
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: CnsColors.red),
              onPressed: account.busy ? null : () => confirmDeleteAccount(context, account),
              icon: const Icon(Icons.delete_forever, size: 18),
              label: const Text('Elimina l’account'),
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

/// "Notifiche": the switch for this phone, and a word about ntfy (the web app's notifications).
class NotificationsCard extends StatelessWidget {
  const NotificationsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = NotificationScope.of(context);
    return SettingsCard(
      title: 'Notifiche',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (store == null)
            const Text('Le notifiche non sono disponibili in questa versione dell’app.')
          else ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: store.on,
              onChanged: store.ready && !store.busy ? store.setOn : null,
              title: const Text(
                'Notifiche su questo telefono',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: CnsColors.text),
              ),
              subtitle: Text(
                store.on
                    ? '✓ Ti avviso qui quando un artista di Controllare pubblica qualcosa, e il giorno delle uscite in arrivo.'
                    : 'Accendile per ricevere qui le uscite nuove: toccando la notifica si apre la pagina Novità.',
              ),
            ),
            if (store.loading || store.busy) const LinearProgressIndicator(minHeight: 2),
            if (store.problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(store.problem!, style: const TextStyle(color: CnsColors.yellow)),
              ),
            const SizedBox(height: 6),
            const Text(
              'Di notte (dalle 23 alle 8) arrivano senza suono. Se ricevi anche quelle di ntfy e ti bastano '
              'queste, togli l’argomento ntfy nelle Impostazioni dell’app web.',
            ),
          ],
        ],
      ),
    );
  }
}

/// "Elimina l'account", after asking: the data in Firebase and the account go away for good.
Future<void> confirmDeleteAccount(BuildContext context, AccountStore account) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Eliminare l’account?'),
      content: const Text(
        'Cancello da Firebase i tuoi artisti con note e segnalibri, le Novità, le uscite in '
        'arrivo, i telefoni registrati per le notifiche e l’account stesso, anche per l’app web. '
        'Non si può annullare: prima, se vuoi, salva la copia di sicurezza.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Annulla')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: CnsColors.red),
          onPressed: () => Navigator.of(dialog).pop(true),
          child: const Text('Elimina'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (await attempt(context, account.deleteAccount)) {
    messenger.showSnackBar(const SnackBar(content: Text('Account eliminato.')));
  }
}
