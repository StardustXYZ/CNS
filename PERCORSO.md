# CNS – Chi Ni Sentimu: il percorso

Repository: https://github.com/StardustXYZ/CNS

Questo file è la mappa del progetto: cosa fare, in che ordine e cosa resta da decidere.
Niente codice qui: ogni passo diventa un branch a parte, provato e unito a `main` solo dopo l'ok.

---

## 1. Da dove prendiamo le uscite: Deezer

Scelta fatta: **Deezer** è la fonte principale; l'ascolto resta su **Spotify**.

### Perché non Spotify (verifica di novembre 2026)

Dall'11 febbraio 2026 le app nuove di Spotify richiedono che il proprietario abbia **Spotify Premium**
(se scade, l'app smette di funzionare). Inoltre: massimo 10 uscite per chiamata, campo che indica i featuring tolto,
limiti di chiamate non pubblicati, regole cambiate tre volte nel 2026.
Fonti: [guida di febbraio 2026](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide),
[modifiche di luglio 2026](https://developer.spotify.com/documentation/web-api/references/changes/july-2026).

### Perché non Genius

È fatto per i testi: le canzoni di un artista si ordinano solo per titolo o popolarità, non per data;
non ha un elenco ufficiale degli album; contiene inediti, pezzi trapelati e traduzioni, che darebbero notifiche false.

### Cosa offre Deezer (provato l'11/11/2026 sulla discografia di Ava Max)

| Cosa | Risultato |
|---|---|
| Chiave, account, abbonamento | **Nessuno**: le chiamate funzionano senza niente |
| Ricerca dell'artista per nome | Funziona (`search/artist`) |
| Discografia di un artista (`artist/{id}/albums`) | Funziona: 114 uscite per Ava Max, a pagine (fino a 100 per pagina) |
| Tipo di uscita | `album`, `single`, `ep` (e `compile` per le raccolte): **gli EP sono distinti** |
| Featuring | Compaiono nella lista, es. "BURN (feat. Ava Max)" del 09/10/2026 |
| Dettagli di un'uscita (`album/{id}`) | Data, copertina in più misure, numero di tracce, durata, etichetta, codice UPC, artisti coinvolti con il ruolo |
| Ordine | **Non** in ordine di data: lo ordina CNS |
| Chiamate dal telefono | Deezer non permette la lettura diretta da una pagina web, ma risponde in modalità "JSONP": la ricerca dall'app si può fare così |
| Protezione contro i bot | Deezer usa una protezione (cookie di Akamai): **da provare dai server di GitHub** |
| Regole d'uso | Gratis per app **personali e non commerciali** (è il nostro caso); vietato salvare l'audio |

### Il prezzo da pagare: il link a Spotify

Senza l'API di Spotify non c'è il link esatto dell'uscita su Spotify
(ho provato song.link, che converte i link: l'accesso gratuito è stato chiuso).
Quindi:
- toccando la notifica si apre **Spotify sulla ricerca** "artista + titolo" (`open.spotify.com/search/...`, che su Android apre l'app): l'uscita è in cima;
- pulsanti della notifica: **"Apri su Spotify"** (la ricerca), **"Apri su Deezer"** (link esatto), **"Apri l'app"**;
- gli stessi pulsanti nella pagina dell'artista e in Recuperando.

Da provare nella Fase 1: che la ricerca su Spotify metta davvero l'uscita giusta al primo posto.

### Uscite annunciate (Fase 6)

Nessuna delle due fonti mostra di solito le uscite future. Candidati gratuiti, da provare sui tuoi artisti:
- **Deezer** stesso: verificare se i preordini compaiono con una data futura;
- **iTunes / Apple Music (ricerca pubblica)**: i preordini compaiono nello store con la data d'uscita;
- **MusicBrainz**: database aperto, ma le date future sono spesso mancanti o approssimative.

---

## 2. Cosa riprendiamo da CNV (senza toccare quella cartella)

| Da CNV | Per CNS |
|---|---|
| `phone/index.html`, `app.js`, `phone.css` | Pagine a hash, menu su una riga, scorrimento tra le pagine, ricerca che non chiude la tastiera, copia di sicurezza in JSON |
| `phone/sw.js` | Uso offline, cache dei dati separata da quella dell'app, file presi dal server a ogni aggiornamento; cache delle copertine come quella delle locandine |
| `phone/manifest.webmanifest`, `icons/` | Stessa struttura, con nome, colori e icona di CNS |
| `app/web/static/style.css` | Tema scuro con le variabili dei colori: l'accento passa da viola a verde |
| `.github/workflows/aggiorna-telefono.yml` | Due giri programmati, stato salvato senza sovrascriverlo per errore, pubblicazione su Pages, riattivazione contro la pausa dei 60 giorni, azioni con Node 24 |
| `.github/workflows/prova-siti.yml` + `app/check_sites.py` | Modello della prova di fattibilità per Deezer, con il riepilogo nella pagina del giro |
| `app/export_static.py` | Costruzione del sito statico con `data.json` |
| `app/services/tmdb.py` + `tests/` | Client asincrono con un "Protocol": i test usano un Deezer finto e non chiamano mai servizi veri |
| `app/services/titles.py` | Base per unire i doppioni (da ampliare: "Deluxe", "Remastered", "Explicit", "(Live)", "Sped Up", ecc.) |
| `app/push.py` | Solo come riferimento: in CNS le notifiche passano da ntfy |

---

## 3. Come è fatto CNS (in breve)

```
Telefono (PWA su GitHub Pages)  <-->  Database gratuito (liste, segnalibri, storico)
   |  cerca gli artisti su Deezer            ^
   |                                         |
GitHub Actions ogni poche ore  --------------+
   |  legge le liste, chiede a Deezer, confronta con le uscite già viste
   v
ntfy  ->  notifica sul telefono  ->  tocco  ->  Spotify si apre sulla ricerca dell'uscita
```

- **Controllo** in Python, come CNV (stesso modo di lavorare, stessi test).
- **App** in HTML/JS semplice, come la versione telefono di CNV.
- **Notifica ntfy**: titolo, tipo e copertina, con i pulsanti descritti sopra.
- Nessun segreto di Deezer da custodire: restano solo la chiave del database e l'argomento ntfy.

### Il database: Firebase (piano Spark, gratuito)

- **Firestore** contiene le liste, i segnalibri, le uscite già viste e lo storico delle Novità.
- **Accesso dall'app**: login con il tuo account Google (Firebase Authentication).
- **Regole di accesso**: solo il tuo account può leggere e scrivere. Tutti gli altri ricevono un rifiuto.
- **Accesso da GitHub**: un "account di servizio" di Firebase, la cui chiave è salvata solo nei segreti di GitHub e nel file `.env`.
- La configurazione web di Firebase (la `apiKey` che finisce nell'app) **non è un segreto**: è pubblica per scelta di Firebase. A proteggere i dati sono le regole di accesso.
- **Nessuna pausa** per inattività. I limiti gratuiti (50.000 letture e 20.000 scritture al giorno) sono molto più alti di quello che serve a un solo utente con pochi artisti.
- **Non usiamo** Cloud Storage e Cloud Functions, che richiedono il piano a pagamento. Le copertine si prendono direttamente da Deezer, e il controllo gira su GitHub.
- Copia di sicurezza: l'esportazione in JSON dall'app (Fase 7). Fino ad allora c'è un'esportazione manuale dalla console di Firebase.

---

## 4. Il percorso a fasi

Ogni casella è un branch a parte (git worktree), con test automatici e prova nel browser a 375 px prima dell'ok.

### Fase 0 – Account e verifiche (da fare tu, niente codice)
- [x] Creare il progetto Firebase gratuito (piano Spark), attivare Firestore e l'accesso con Google; creare l'account di servizio per GitHub. Fatto l'11/11/2026: progetto `cns-chi-ni-sindimu`, Firestore in modalità produzione, accesso Google con il dominio `stardustxyz.github.io`, app web "CNS telefono", chiave dell'account di servizio salvata fuori dal repository.
- [x] Rendere pubblico il repository `StardustXYZ/CNS` e attivare Pages con "GitHub Actions".
- [x] Installare ntfy sul telefono e iscriversi a un argomento con un nome lungo e casuale (provato con un messaggio dal browser).
- [x] Mettere i segreti su GitHub (Settings → Secrets): `FIREBASE_SERVICE_ACCOUNT` e `NTFY_TOPIC`. Sul PC vanno solo nel file `.env`.
- Il Premium di Spotify non serve più: puoi toglierlo quando vuoi.

### Fase 1 – Prova di fattibilità (il primo codice)
- [x] Workflow "Prova Deezer": dai server di GitHub, discografia completa dei tuoi 7 artisti; conteggio di chiamate, tempi ed eventuali blocchi della protezione contro i bot. Riepilogo nella pagina del giro. **Riuscita il 12/11/2026**: nessun blocco, tutti e 7 gli artisti letti (16 chiamate, circa 6 secondi dal PC).
- [x] Prova di una notifica ntfy con copertina e pulsanti. **Riuscita il 12/11/2026**: il tocco apre Spotify sulla ricerca giusta; tutti e tre i pulsanti funzionano.
- ~~Prova della ricerca di un artista dal telefono (JSONP)~~ → spostata nella Fase 3, dove si costruisce la ricerca (dal PC Deezer risponde in JSONP).
- Cose scoperte:
  - la ricerca per nome su Deezer non mette sempre l'artista giusto per primo (Amy Lee è il 5° risultato): si sceglie quello con il nome identico e più fan;
  - Android mostra al massimo 3 pulsanti e ntfy ne aggiunge 2 per una copertina allegata: la copertina va come **icona piccola** (impostazione `BIG_COVER` per tornare a quella grande con il solo pulsante di Spotify);
  - Deezer non mostra le uscite future (0 per tutti): le anteprime della Fase 6 avranno bisogno di un'altra fonte;
  - dal titolo si riconoscono pochi featuring (2 per Ava Max): nella Fase 3 si useranno gli artisti di ogni uscita;
  - la prova riparte da sola quando cambiano la prova, il client Deezer o la notifica, e manda una notifica di prova.

### Fase 2 – Scheletro (da CNV)
- [ ] PWA vuota con le pagine Controllare, Recuperando, Novità, Impostazioni: menu su una riga, scorrimento, tema scuro verde e nero, service worker, manifest, icona.
- [ ] Workflow principale: due giri programmati, riattivazione dei 60 giorni, azioni con Node 24, pubblicazione su Pages.
- [ ] Test automatici con il Deezer finto.
- [ ] Collegamento a Firebase: login Google nell'app, regole di accesso (solo tu puoi leggere e scrivere), lettura e scrittura da GitHub con l'account di servizio. Test delle regole con l'emulatore di Firebase, senza toccare i dati veri.

### Fase 3 – Artisti
- [ ] Ricerca dell'artista per nome su Deezer dal telefono (JSONP, da provare per prima cosa); in alternativa, link Deezer incollato. L'elenco mostra foto e numero di fan per scegliere quello giusto.
- [ ] Aggiunta dell'artista con ID, foto e nome.
- [ ] Pagina dell'artista: tutte le uscite in ordine di data (album, singoli, EP, featuring, raccolte), con i doppioni uniti (deluxe, explicit/clean, ripubblicazioni) e i pulsanti Spotify e Deezer.

### Fase 4 – Controllare (il cuore)
- [ ] Lista "Controllare" con la nota per artista e i tipi da segnalare (tutti accesi di default, featuring compresi).
- [ ] Controllo su GitHub ogni poche ore: uscite nuove rispetto a quelle già viste.
- [ ] **Prima esecuzione silenziosa** per ogni artista appena aggiunto: segna tutto come visto, senza notifiche.
- [ ] Notifica ntfy con titolo, tipo, copertina e pulsanti; più uscite insieme diventano una notifica sola.
- [ ] Pagina "Novità": lo storico delle uscite notificate.

### Fase 5 – Recuperando
- [ ] Lista "Recuperando": per ogni artista la coda in ordine cronologico con il segnalibro.
- [ ] Pulsanti Ascoltato (il segnalibro avanza) e Salta.
- [ ] Le uscite nuove finiscono in fondo alla coda.
- [ ] Fine della discografia: sposta in Controllare / tieni / archivia, più l'opzione "sposta in automatico".
- [ ] Inserimento delle tue liste di esempio (Ava Max, Lady Gaga, Isabel LaRosa, Arctic Monkeys, K/DA; League of Legends fino a "Take Over", Amy Lee fino a "Aftermath").

### Fase 6 – Anteprime
- [ ] Prova di fattibilità di Deezer, iTunes e MusicBrainz sui tuoi artisti; si sceglie la fonte migliore.
- [ ] "Esce il …" nella pagina dell'artista e nelle Novità, con un promemoria ntfy il giorno dell'uscita.

### Fase 7 – Rifiniture
- [ ] Copia di sicurezza ed esportazione delle liste in JSON.
- [ ] Layout per il PC.
- [ ] Telegram come seconda notifica (facoltativo).

### Fase 8 – Lettore MP3 (progetto a parte, più avanti)
- [ ] Importazione dei file scelti dal telefono, salvati nello spazio dell'app.
- [ ] Libreria per artista e album dai tag, con i featuring divisi ("feat.", "&", ",").
- [ ] Playlist e riproduzione in background con i comandi nella schermata di blocco.
- [ ] Per ogni artista, le canzoni della discografia Deezer non ancora scaricate.

---

## 5. Decisioni prese (11/11/2026)

1. ~~Database~~ → deciso: **Firebase** (vedi "Il database" più sotto).
2. ~~Nome~~ → deciso: **CNS – Chi Ni Sentimu**.
3. ~~Colori e icona~~ → deciso: verde **#008000** su nero; icona nera con le cuffie verdi.
   - #008000 si usa per l'icona, i pulsanti (con il testo bianco sopra si legge bene), il menu attivo e la barra del telefono.
   - Per i testi piccoli e i link sul nero, #008000 è troppo scuro (contrasto 3,3: per leggere bene serve almeno 4,5). Lì si usa lo stesso verde più chiaro, **#33A833** (contrasto 5,4).
   - È diverso dal verde di Spotify (#1DB954), così CNS non sembra un'app di Spotify.
4. **Notifiche**:
   - ~~frequenza~~ → deciso: **ogni 3 ore**, 8 giri al giorno, a minuti "strani" (es. :17) perché allo scoccare dell'ora GitHub è più carico e ritarda di più. Con 8 giri non serve il giro doppio di CNV: se uno salta, c'è il successivo;
   - ~~notte~~ → deciso: **dalle 23 alle 8 (ora italiana) le notifiche arrivano senza suono** (priorità bassa di ntfy); i controlli continuano anche di notte. Gli orari si potranno cambiare dalle Impostazioni;
   - ~~raggruppamento~~ → deciso: **fino a 3 uscite, una notifica per ognuna** (copertina e pulsanti); **da 4 in su, una notifica sola** ("5 uscite nuove: Ava Max, Lady Gaga…") che apre la pagina Novità.
5. ~~Featuring~~ → deciso: **segnalati di default** per ogni artista nuovo; si spengono artista per artista.

---

## 6. Regole fisse di lavoro

- Una funzione alla volta: un branch per funzione in una cartella separata (git worktree); merge in `main` solo dopo l'ok.
- Dopo ogni modifica: test automatici, poi prova nel browser a 375 px con screenshot; si dice cosa è stato provato e cosa no.
- Commit in italiano, numerati in inglese da "First Commit":
  riga 1 `<Ordinale> Commit`, riga 2 titolo generale, poi una riga per cambiamento con `+` aggiunte, `-` tolte, `~` modifiche.
- Il messaggio di commit si propone sempre prima; commit, merge e push solo dopo l'ok.
- Nessun riferimento all'AI nei commit e nel progetto.
- Segreti mai nel repository: solo `.env` (in `.gitignore`) e segreti di GitHub; controllo prima di ogni commit.
- Tutto il testo dell'app è in italiano.
