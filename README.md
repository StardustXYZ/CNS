# CNS – Chi Ni Sentimu

Le uscite nuove degli artisti che segui, e le discografie da recuperare dall'inizio.

- **Controllare**: gli artisti con cui sei in pari. Quando pubblicano qualcosa ti arriva una
  notifica, e anche quando annunciano un'uscita (pre-order su iTunes) e il giorno in cui esce.
- **Recuperando**: le discografie da ascoltare dalla prima uscita, con il segnalibro, i doppioni
  (remix, deluxe, versioni) uniti sotto l'originale e la spunta per canzone.
- **Novità**: le uscite nuove e quelle in arrivo, con Spotify, Deezer e Apple Music a un tocco.

L'accesso è solo su invito: chi gestisce CNS aggiunge la tua email alla lista delle persone ammesse.

## Le parti

| Parte | Dove | Cosa fa |
|---|---|---|
| App web | `web/`, pubblicata su GitHub Pages | Le liste, la discografia, Novità e Impostazioni, anche sul PC |
| App Android | `mobile/` (Flutter) | Le stesse pagine, più notifiche native, widget, importazione e scelta a caso |
| Controllo | `app/` (Python), su GitHub Actions ogni 3 ore | Cerca le uscite su Deezer e iTunes e manda le notifiche (ntfy e app) |
| Regole | `firebase/firestore.rules` | Chi può leggere e scrivere cosa in Firebase |

Le due app leggono e scrivono gli stessi dati di Firebase: puoi usarle insieme.

## Installare l'app Android

Scarica l'APK dell'ultima versione dalla pagina
[Releases](https://github.com/StardustXYZ/CNS/releases) (quelle che iniziano con `app-v`),
aprilo sul telefono e conferma l'installazione. Quando esce una versione nuova, l'app te lo
dice e la scarichi dallo stesso posto.

## Per chi sviluppa

- Prove: `python -m pytest` (controllo), `node --test web/test/*.test.mjs` (app web),
  `npm test` in `firebase/` (regole), `flutter test` in `mobile/` (app Android).
- Le librerie Python hanno la versione fissata in `constraints.txt` (si installano con
  `pip install -e ".[dev]" -c constraints.txt`, come fanno i workflow). Per aggiornarne una:
  cambia la sua riga, prova `python -m pytest` e committa.
- I segreti (chiave dell'account di servizio, argomento ntfy) stanno nel file `.env` e nei
  segreti di GitHub; `google-services.json`, la chiave di firma e `key.properties` restano sul PC.
  Nessuno di questi va mai nel repository.
- Il percorso del progetto, fase per fase, è in [PERCORSO.md](PERCORSO.md).
