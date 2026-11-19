import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/account.dart';
import '../theme.dart';

/// Gives the pages the account (and rebuilds them when it changes).
class AccountScope extends InheritedNotifier<AccountStore> {
  const AccountScope({super.key, required AccountStore store, required super.child}) : super(notifier: store);

  static AccountStore of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AccountScope>()!.notifier!;
}

/// A short message at the bottom of the screen.
void say(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// Runs an account action and shows its error, if any.
Future<bool> attempt(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } on AccountError catch (err) {
    if (context.mounted) say(context, err.message);
  } catch (err) {
    if (context.mounted) say(context, 'Qualcosa non ha funzionato: $err');
  }
  return false;
}

/// "Esci dall'account", after asking.
Future<void> confirmSignOut(BuildContext context, AccountStore account) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Uscire dall’account?'),
      content: const Text('I tuoi artisti restano salvati nell’account: li ritrovi quando rientri.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Annulla')),
        FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Esci')),
      ],
    ),
  );
  if (ok == true && context.mounted) await attempt(context, account.signOut);
}

/// CNS works only with an admitted account (the artists are in Firebase): until then this
/// screen takes the place of the app, with the way to sign in, confirm the e-mail or ask to
/// be added to the list.
class AccessGate extends StatelessWidget {
  const AccessGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.of(context);
    final user = account.user;
    if (user != null && user.verified && account.admission == Admission.admitted) return child;

    final children = <Widget>[];
    void text(String s, {Color color = CnsColors.textMuted}) => children.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(s, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: color, height: 1.4)),
        ));

    if (!account.available) {
      text('L’accesso non è disponibile in questa versione dell’app.', color: CnsColors.yellow);
    } else if (user == null) {
      text('Le uscite degli artisti che segui e le discografie da recuperare. '
          'L’accesso è solo su invito: se non sei nella lista, chiedi di aggiungerti.');
      children.addAll([
        FilledButton.icon(
          onPressed: account.busy ? null : () => attempt(context, account.signInWithGoogle),
          icon: const Icon(Icons.account_circle),
          label: const Text('Accedi con Google'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: account.busy
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EmailLoginPage(account: account))),
          icon: const Icon(Icons.mail_outline),
          label: const Text('Accedi con email e password'),
        ),
      ]);
    } else {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(user.email, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ));
      if (!user.verified) {
        text('Ti ho mandato un’email di conferma a ${user.email}. Apri il link che contiene (guarda anche nello spam), '
            'poi torna qui e tocca “Ho confermato”.', color: CnsColors.yellow);
        children.addAll([
          FilledButton(
            onPressed: account.busy
                ? null
                : () => attempt(context, () async {
                      if (!await account.reloadVerified() && context.mounted) {
                        say(context, 'L’email non risulta ancora confermata.');
                      }
                    }),
            child: const Text('Ho confermato'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: account.busy
                ? null
                : () => attempt(context, () async {
                      await account.sendVerification();
                      if (context.mounted) say(context, 'Email di conferma mandata di nuovo.');
                    }),
            child: const Text('Rimanda l’email'),
          ),
        ]);
      } else {
        switch (account.admission) {
          case Admission.none:
          case Admission.checking:
          case Admission.admitted:
            children.add(const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Controllo se sei nella lista…', style: TextStyle(fontSize: 14, color: CnsColors.textMuted)),
              ]),
            ));
          case Admission.notAdmitted:
            text('Il tuo account non è tra le persone ammesse a CNS. Chiedi a chi ti ha dato l’app di aggiungere '
                '${user.email}, poi tocca “Riprova”.', color: CnsColors.yellow);
          case Admission.error:
            text('Non riesco a controllare se sei nella lista. Controlla la connessione e riprova.', color: CnsColors.yellow);
        }
        if (account.admission == Admission.notAdmitted || account.admission == Admission.error) {
          children.add(FilledButton(onPressed: account.busy ? null : account.checkAdmission, child: const Text('Riprova')));
        }
      }
      children.addAll([
        const SizedBox(height: 8),
        UserCode(uid: user.uid),
        TextButton.icon(
          onPressed: account.busy ? null : () => confirmSignOut(context, account),
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Esci dall’account'),
        ),
      ]);
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.headphones, size: 72, color: CnsColors.green),
                  const SizedBox(height: 8),
                  const Text('CNS',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
                  const Text('Chi Ni Sindimu',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, fontStyle: FontStyle.italic, color: CnsColors.textMuted)),
                  const SizedBox(height: 24),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Codice utente: …" with the button to copy it (the administrator pastes it in the console).
class UserCode extends StatelessWidget {
  const UserCode({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text('Codice utente: $uid',
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: CnsColors.textMuted)),
        ),
        IconButton(
          tooltip: 'Copia il codice utente',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.copy, size: 16),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: uid));
            if (context.mounted) say(context, 'Codice utente copiato.');
          },
        ),
      ],
    );
  }
}

/// Sign in or create an account with e-mail and password, or get a new password.
class EmailLoginPage extends StatefulWidget {
  const EmailLoginPage({super.key, required this.account});

  final AccountStore account;

  @override
  State<EmailLoginPage> createState() => _EmailLoginPageState();
}

class _EmailLoginPageState extends State<EmailLoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _hidden = true;
  String? _problem;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim(), password = _password.text;
    setState(() => _problem = !looksLikeEmail(email)
        ? 'Scrivi un indirizzo email valido.'
        : password.length < 6
            ? 'La password deve avere almeno 6 caratteri.'
            : null);
    if (_problem != null) return;
    try {
      await (_register ? widget.account.register(email, password) : widget.account.signInWithEmail(email, password));
      if (mounted) Navigator.of(context).pop();
    } on AccountError catch (err) {
      if (mounted) setState(() => _problem = err.message); // under the fields, where the eyes are
    } catch (err) {
      if (mounted) setState(() => _problem = 'Qualcosa non ha funzionato: $err');
    }
  }

  Future<void> _reset() async {
    final email = _email.text.trim();
    if (!looksLikeEmail(email)) {
      setState(() => _problem = 'Scrivi prima la tua email, poi tocca di nuovo “Password dimenticata?”.');
      return;
    }
    final ok = await attempt(context, () => widget.account.sendPasswordReset(email));
    if (ok && mounted) say(context, 'Ti ho mandato un’email per scegliere una nuova password.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.account,
      builder: (context, _) {
        final busy = widget.account.busy;
        return Scaffold(
          appBar: AppBar(title: Text(_register ? 'Crea un account' : 'Accedi con email')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Ho già un account')),
                  ButtonSegment(value: true, label: Text('Sono nuovo')),
                ],
                selected: {_register},
                onSelectionChanged: (s) => setState(() {
                  _register = s.first;
                  _problem = null;
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: _hidden,
                autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: _register ? 'Almeno 6 caratteri' : null,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _hidden ? 'Mostra la password' : 'Nascondi la password',
                    icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  ),
                ),
              ),
              if (_problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_problem!, style: const TextStyle(color: CnsColors.red)),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy ? null : _submit,
                child: Text(busy ? 'Un momento…' : (_register ? 'Crea l’account' : 'Accedi')),
              ),
              if (_register)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('Ti arriva un’email di conferma: l’account vale solo dopo aver aperto il suo link.',
                      style: TextStyle(fontSize: 12, color: CnsColors.textMuted)),
                )
              else
                TextButton(onPressed: busy ? null : _reset, child: const Text('Password dimenticata?')),
            ],
          ),
        );
      },
    );
  }
}

/// The administrator's page: the e-mails admitted to CNS (config/ammessi.email).
class AllowListPage extends StatefulWidget {
  const AllowListPage({super.key, required this.account});

  final AccountStore account;

  @override
  State<AllowListPage> createState() => _AllowListPageState();
}

class _AllowListPageState extends State<AllowListPage> {
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final email = _email.text.trim().toLowerCase();
    if (!looksLikeEmail(email)) {
      say(context, 'Scrivi un indirizzo email valido.');
      return;
    }
    final list = widget.account.allowed ?? const [];
    if (list.contains(email)) {
      say(context, '$email è già nella lista.');
      return;
    }
    if (list.length >= maxAllowed) {
      say(context, 'La lista può avere al massimo $maxAllowed email.');
      return;
    }
    if (await attempt(context, () => widget.account.setAllowList([...list, email]))) _email.clear();
  }

  Future<void> _remove(String email) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Togliere dalla lista?'),
        content: Text('$email non potrà più entrare in CNS e non riceverà più notifiche. I suoi artisti restano salvati.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Togli')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await attempt(context, () => widget.account.setAllowList([...?widget.account.allowed]..remove(email)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.account,
      builder: (context, _) {
        final list = widget.account.allowed ?? const <String>[];
        return Scaffold(
          appBar: AppBar(title: const Text('Persone ammesse')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                  'Chi è in questa lista può entrare in CNS con Google, oppure con email e password '
                  '(l’email va confermata). Ognuno vede solo i suoi artisti; tu non vedi i loro. '
                  'La stessa lista vale anche per l’app web.',
                  style: TextStyle(fontSize: 13, color: CnsColors.textMuted, height: 1.35)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      onSubmitted: (_) => _add(),
                      decoration: const InputDecoration(
                          labelText: 'Email da aggiungere', border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: widget.account.busy ? null : _add, child: const Text('Aggiungi')),
                ],
              ),
              const SizedBox(height: 14),
              if (list.isEmpty) const Text('Nessuno per ora, a parte te.', style: TextStyle(color: CnsColors.textMuted)),
              for (final email in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(email),
                  trailing: IconButton(
                    tooltip: 'Togli $email',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: widget.account.busy ? null : () => _remove(email),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
