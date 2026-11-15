import 'package:flutter/material.dart';

import '../theme.dart';
import 'account_pages.dart';

/// Impostazioni: the account (with the allow list for the administrator); notifications and
/// the backup copy arrive in the next phases.
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
          child: Text('Le notifiche sul telefono arrivano in una delle prossime versioni. '
              'Intanto restano quelle di ntfy, che scegli nell’app web.'),
        ),
        SettingsCard(
          title: 'Copia di sicurezza',
          child: Text('Arriva in una delle prossime versioni, compatibile con quella dell’app web.'),
        ),
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
          DefaultTextStyle.merge(style: const TextStyle(fontSize: 13, color: CnsColors.textMuted, height: 1.4), child: child),
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
          Text(name.isNotEmpty ? '$name · ${user.email}' : user.email,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: CnsColors.text)),
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
