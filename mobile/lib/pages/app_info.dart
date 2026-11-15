import 'package:flutter/material.dart';

import '../data/updates.dart';
import '../theme.dart';
import 'account_pages.dart' show say;
import 'impostazioni_page.dart' show SettingsCard;
import 'widgets.dart' show openLink;

/// Gives the pages the update check (null in the tests).
class UpdateScope extends InheritedNotifier<UpdateStore> {
  const UpdateScope({super.key, required UpdateStore? store, required super.child}) : super(notifier: store);

  static UpdateStore? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<UpdateScope>()?.notifier;
}

/// Opens the APK in the browser, which downloads it; then the person opens the file to install.
Future<void> downloadUpdate(BuildContext context, AppRelease release) async {
  await openLink(context, release.apkUrl);
  if (!context.mounted) return;
  say(
    context,
    'Quando il download finisce, apri il file e tocca Aggiorna. Se Android lo chiede, permetti '
    'l’installazione dal browser. I tuoi artisti restano nell’account.',
  );
}

/// The notice at the top of the app when a newer version is out.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final store = UpdateScope.of(context);
    if (store == null || !store.showNotice) return const SizedBox();
    final release = store.available!;
    return Material(
      color: CnsColors.green.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.system_update, color: CnsColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text('È uscita la versione ${release.version} di CNS',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ]),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: store.dismiss, child: const Text('Non ora')),
                FilledButton(onPressed: () => downloadUpdate(context, release), child: const Text('Scarica')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// At the bottom of Impostazioni: the version, the check for a new one, and the privacy note.
class AppInfoCard extends StatelessWidget {
  const AppInfoCard({super.key, required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final store = UpdateScope.of(context);
    String status;
    if (store == null) {
      status = '';
    } else if (store.checking) {
      status = 'Controllo se c’è una versione nuova…';
    } else if (store.problem != null) {
      status = store.problem!;
    } else if (store.available != null) {
      status = 'È uscita la versione ${store.available!.version}.';
    } else if (store.checkedAt != null) {
      status = 'Hai l’ultima versione.';
    } else {
      status = '';
    }
    return SettingsCard(
      title: 'App',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('CNS per Android, versione $version.'),
          if (status.isNotEmpty) Text(status),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (store != null && store.available != null)
              FilledButton.icon(
                onPressed: () => downloadUpdate(context, store.available!),
                icon: const Icon(Icons.download),
                label: Text('Scarica la ${store.available!.version}'),
              )
            else if (store != null)
              OutlinedButton.icon(
                onPressed: store.checking ? null : store.check,
                icon: const Icon(Icons.refresh),
                label: const Text('Controlla gli aggiornamenti'),
              ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyPage())),
              icon: const Icon(Icons.privacy_tip_outlined),
              label: const Text('Privacy'),
            ),
          ]),
        ],
      ),
    );
  }
}

/// "Privacy": what CNS keeps, where, who sees it, and how to delete it. In plain words.
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  static const sections = [
    (
      'Cosa salva CNS',
      'L’account usa Firebase, un servizio di Google. Lì sono salvati: la tua email (e il nome, se entri '
          'con Google), gli artisti che segui con le loro liste e note, il segnalibro e le canzoni spuntate, '
          'i tipi di uscita per cui vuoi gli avvisi, le Novità e le uscite in arrivo trovate per te, '
          'l’argomento ntfy se lo hai scelto, e un codice per ogni telefono dove hai acceso le notifiche.'
    ),
    (
      'Sul telefono',
      'L’app tiene una copia delle discografie scaricate da Deezer, per aprirle subito, e la data in cui hai '
          'guardato le Novità. Le copertine e le foto arrivano da Deezer; le uscite annunciate da iTunes.'
    ),
    (
      'Chi vede i tuoi dati',
      'Nell’app nessun altro: ogni account legge e scrive solo i suoi dati. Chi gestisce CNS vede nell’app '
          'solo la lista delle email ammesse. Ha però accesso alla console di Firebase, dove i dati si '
          'potrebbero vedere: non li guarda, non li condivide e non li usa per altro.'
    ),
    (
      'Controllo e notifiche',
      'Ogni tre ore un programma su GitHub controlla su Deezer e iTunes gli artisti che segui e, se c’è '
          'qualcosa di nuovo, lo scrive nelle tue Novità e ti manda la notifica (ntfy e/o questo telefono). '
          'Nel registro pubblico di GitHub scrive solo numeri: mai nomi di artisti, email o codici.'
    ),
    (
      'Cosa non fa',
      'Niente pubblicità, niente statistiche su come usi l’app, niente dati venduti o dati a terzi oltre a '
          'Google (Firebase), GitHub, Deezer e iTunes, che servono per farla funzionare.'
    ),
    (
      'Cancellare i dati',
      'In Impostazioni, «Elimina l’account» cancella da Firebase i tuoi artisti, le Novità, le uscite in '
          'arrivo, i telefoni registrati e l’account stesso. Non si può annullare: prima, se vuoi, salva la '
          'copia di sicurezza.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (title, text) in sections) ...[
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(text, style: const TextStyle(fontSize: 14, height: 1.45, color: CnsColors.text)),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}
