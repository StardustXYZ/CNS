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
Divisa in tre branch, uno per funzione.

**2a – App e pubblicazione**
- [x] PWA vuota con le pagine Controllare, Recuperando, Novità, Impostazioni: menu su una riga, scorrimento tra le pagine, tema scuro verde e nero, service worker, manifest, icona (cuffie #008000 su nero, disegnate da `tools/crea_icone.py`).
- [x] Costruzione del sito (`app/build_site.py`) con la versione nel service worker, e workflow "Pubblica il sito" su GitHub Pages quando cambia l'app su `main`.
- [x] Test automatici della costruzione del sito.
- [x] Prova sul telefono dopo la pubblicazione: installazione sulla schermata Home e apertura senza connessione. **Riuscita il 12/11/2026** (prima Pages andava riattivato in Settings).

**2b – Firebase**
- [x] Regole di accesso (`firebase/firestore.rules`): solo il codice utente del proprietario legge e scrive; finché il codice non è inserito, nessuno entra. Provate con l'emulatore (5 prove, progetto finto `demo-cns`).
- [x] Login Google nell'app (Impostazioni): nome, email, codice utente da copiare, "Esci"; avviso nelle liste finché non si fa l'accesso. Il codice di Firebase viene salvato dal service worker per l'uso offline.
- [x] Lettura e scrittura da GitHub con l'account di servizio (`app/services/firestore.py`, API REST) e "Prova Firebase", che scrive l'ora del contatto in `stato/github`: l'app la mostra in Impostazioni.
- [x] Workflow "Test" a ogni push (Python e regole) e "Regole Firebase" per pubblicare le regole.
- ~~Codice utente nel segreto `OWNER_UID`~~ → superato dalla 3a: le regole sono diventate per utente (12/11/2026). La pubblicazione da GitHub è fallita perché l'account di servizio non ha il ruolo "Firebase Rules Admin": le regole si incollano a mano in Firebase → Firestore → Regole, oppure si dà quel ruolo all'account di servizio.

Ordine deciso il 12/11/2026: prima la **3a** (vedere e aggiungere gli artisti), poi la **2c** e la **2d**.

**2c – Controllo programmato**
- [x] Workflow "Controllo delle uscite" ogni 3 ore al minuto 17, riattivazione contro la pausa dei 60 giorni (da CNV), azioni con Node 24.
- [x] Per ora legge gli artisti di tutti gli utenti (`app/controllo.py`), li raggruppa per artista Deezer e segna il giro in `stato/github`. Il confronto con le uscite e le notifiche arrivano nella Fase 4.
- [x] Il registro del giro è pubblico: contiene solo numeri, mai nomi di artisti o codici utente (c'è un test apposta).
- [x] Nell'app, Impostazioni → "Ultimo controllo da GitHub", con un avviso se GitHub non controlla da più di 9 ore.
- [ ] Primo giro automatico verificato su GitHub.

**2d – Multiutenza (amici e familiari, come in CNV)**
- [x] Dati per utente: ogni account Google ha la sua cartella `utenti/{codice}` e vede solo quella (fatto nella 3a).
- [x] Il controllo raggruppa gli artisti: uno seguito da più persone viene chiesto a Deezer una volta sola (fatto nella 2c).
- [x] Lista degli ammessi (`config/ammessi`): l'amministratore è il codice utente scritto una volta a mano nella console (non si cambia dall'app); le email ammesse si aggiungono e tolgono in Impostazioni → "Persone ammesse", visibile solo all'amministratore. Le regole fanno entrare solo l'amministratore e le email verificate della lista (senza badare alle maiuscole); senza la lista non entra nessuno. 15 prove delle regole.
- [x] Chi non è ammesso vede "Il tuo account (…) non è tra le persone ammesse a CNS".
- [x] Il controllo su GitHub salta chi è stato tolto dalla lista (l'app salva l'email di ognuno nelle sue impostazioni).
- [x] Argomento ntfy per utente, salvato nelle sue impostazioni (fatto nella Fase 4).
- [x] Sul telefono: lista degli ammessi creata nella console (`config` → `ammessi` → campo `admin`, tipo string), regole incollate. **Riuscita il 13/11/2026.** Da ricordare: il codice utente va **incollato** con "Copia codice", non riscritto, perché "l" minuscola e "1" si confondono.
- [x] Messaggio corretto anche nel riquadro "Ultimo controllo da GitHub" per chi non è ammesso.
- [ ] Pubblicazione delle regole da GitHub: dare all'account di servizio il ruolo "Firebase Rules Admin" (console di Google Cloud → IAM), poi Actions → "Regole Firebase" → Run workflow. Il workflow resta da avviare a mano, per scegliere il momento giusto.

### Fase 3 – Artisti

**3a – Liste e aggiunta**
- [x] Ricerca dell'artista per nome su Deezer dal telefono (JSONP, funziona); in alternativa, link Deezer incollato. I risultati mostrano foto, fan e numero di uscite; prima il nome identico con più fan.
- [x] Aggiunta a Controllare o Recuperando, con foto, nome, link e fan; contatori nel menu.
- [x] Pagina dell'artista: lista (Controllare / Recuperando / Archivio), nota, "Apri su Deezer", "Togli dalle liste". L'Archivio è in fondo a Recuperando.
- [x] Regole per utente con controllo dei dati (nome, lista valida, codice Deezer numerico, nota fino a 500 caratteri): 7 prove sull'emulatore.
- [x] Sul telefono: regole pubblicate (incollate a mano nella console), accesso con Google, aggiunta dei tuoi artisti. **Riuscita il 13/11/2026.**

**3b – Discografia**
- [x] Pagina dell'artista: tutte le uscite da Deezer (tutte le pagine), con filtri per tipo (Album, EP, Singoli, Featuring, Raccolte) e ordine per data. In Recuperando parte dalla più vecchia, altrove dalla più recente.
- [x] Doppioni uniti (`web/discografia.js`): remix, Deluxe/Edition, explicit/clean, versioni acustiche, live e strumentali, "feat." di altri finiscono sotto l'originale come "+N versioni". Un album e il singolo con lo stesso nome restano separati; un EP e la sua versione deluxe sono la stessa uscita. Sui dati veri: Ava Max da 114 a 51 uscite, Lady Gaga da 82 a 50.
- [x] Pulsanti "Spotify" (ricerca artista + titolo) e "Deezer" (link esatto) su ogni uscita.
- [x] Copia della discografia sul telefono: si apre subito e anche offline; si chiede di nuovo a Deezer dopo 6 ore.
- [x] Sul telefono. **Riuscita il 13/11/2026.**
- Da ricordare per la Fase 4: il controllo su GitHub dovrà usare le stesse regole per i doppioni (in Python), così una versione nuova di un'uscita già vista non arriva come "uscita nuova".

### Fase 4 – Controllare (il cuore)
- [x] Nella pagina di un artista in Controllare, "Avvisi": i tipi da segnalare (tutti accesi di default, featuring compresi).
- [x] Controllo su GitHub ogni 3 ore (`app/controllo.py`): per ogni artista la discografia di Deezer confrontata con le uscite già viste (`visti/<codice Deezer>`, chiuso all'app). Un artista seguito da più persone si chiede a Deezer una volta sola.
- [x] **Prima volta silenziosa**: un artista mai controllato prima diventa "già visto" per intero, senza notifiche.
- [x] Non sono uscite nuove: le versioni di un'uscita già vista (remix, deluxe…: stesse regole dell'app, in `app/services/discografia.py`, con esempi condivisi tra Python e JavaScript in `tests/fixtures/doppioni.json`) e le uscite più vecchie di 30 giorni che Deezer aggiunge al catalogo in ritardo.
- [x] Notifiche solo per gli artisti in Controllare (in Recuperando l'uscita va in fondo alla coda), sull'argomento ntfy di ogni persona (Impostazioni, con "Manda una prova"). Fino a 3 uscite una notifica ciascuna; da 4 in su una sola che apre le Novità. Di notte senza suono.
- [x] Pagina "Novità": lo storico delle uscite notificate, con Spotify e Deezer, il contatore nel menu delle nuove e "Svuota le Novità". Senza argomento ntfy le uscite arrivano solo qui.
- [x] Regole di Firebase: Novità leggibili e cancellabili ma scritte solo da GitHub; argomento ntfy controllato (10 prove sull'emulatore). **Vanno incollate di nuovo nella console.**
- [x] Prova completa sull'emulatore con il Deezer vero: primo giro silenzioso (114 uscite di Ava Max ricordate), uscita nuova simulata → Novità e notifica all'argomento giusto, terzo giro senza ripetizioni.
- [ ] Sul telefono: regole incollate, argomento ntfy in Impostazioni con "Manda una prova", primo giro silenzioso su GitHub.

### Fase 5 – Recuperando (fatta prima della Fase 4, su tua scelta del 13/11/2026)
- [x] Lista "Recuperando": per ogni artista "12 di 51 · prossima: …" con la barra di avanzamento.
- [x] Pagina dell'artista: sezione "Segnalibro" con la prossima uscita (Spotify e Deezer), Ascoltato, Salta e "Annulla l'ultimo". Nella discografia ogni uscita mostra "✓ Ascoltato" / "Saltato" (con "annulla") oppure "Arrivato qui", che segna tutto fino a quella uscita.
- [x] Le uscite nuove finiscono in fondo alla coda (sono le più recenti); un nuovo remix di un'uscita già ascoltata non torna nella coda.
- [x] Cosa recuperare, per artista: Album, EP, Singoli, Featuring (di default) e Raccolte (escluse di default).
- [x] Fine della discografia: sposta in Controllare / tieni qui / archivia, più l'opzione "sposta in automatico in Controllare".
- [x] Logica in `web/segnalibro.js`, con 6 test. Il segnalibro è salvato su Firebase nel documento dell'artista (`fatte`), quindi vale su tutti i tuoi dispositivi.
- [x] Sul telefono: League of Legends fino a "Take Over" e Amy Lee fino a "Aftermath" con «Arrivato qui». **Riuscita il 13/11/2026.**

### Fase 6 – Anteprime
- [x] Prova di fattibilità dal PC (13/11/2026), con i tuoi artisti più 13 molto noti e due preordini veri (ENHYPEN 20/11, Justice 11/12):
  - **iTunes / Apple Music** (ricerca pubblica, senza chiavi): mostra i preordini con la data futura ed è aggiornato → **scelto** (decisione del 13/11/2026);
  - **Deezer**: non mostra le uscite future;
  - **MusicBrainz**: rifiuta quasi tutte le richieste anonime (errore 503); servirebbe mandargli un contatto.
- [x] Client iTunes (`app/services/itunes.py`): circa 20 chiamate al minuto come chiede Apple; l'artista giusto è quello con il nome uguale e più titoli in comune con Deezer (cinque "Justice" su iTunes). Se il nome su iTunes è più lungo ("League of Legends Music") vale solo con almeno 3 titoli in comune. Dal PC: tutti e 9 gli artisti abbinati giusti.
- [x] Prova da GitHub ("Prova iTunes"): **riuscita il 13/11/2026**, Apple risponde anche dai server di GitHub, tutti e 9 gli artisti letti.
- [x] Nel controllo ogni 3 ore (`app/anteprime.py`), per gli artisti in Controllare e i tipi scelti negli Avvisi: notifica "In arrivo: … esce il …" una volta sola; se la data cambia si aggiorna senza un'altra notifica; promemoria "Esce oggi" il giorno dell'uscita; quando poi l'uscita arriva su Deezer niente seconda notifica (resta nello storico delle Novità); una settimana dopo l'annuncio sparisce. L'abbinamento con iTunes si salva e, se non c'è, si riprova dopo 7 giorni.
- [x] Nell'app: "In arrivo" in cima a Novità e nella pagina dell'artista, con "esce il … (tra N giorni)", Apple Music e, il giorno dell'uscita, Spotify.
- [x] Regole di Firebase: anteprime scritte solo da GitHub (11 prove). **Vanno incollate di nuovo nella console.**
- [x] Prova sull'emulatore con Deezer e iTunes veri: ENHYPEN e Justice in Controllare → due notifiche "In arrivo" (20/11 e 11/12), nessuna ripetizione al secondo giro, sezione "In arrivo" nell'app.
- [x] Pubblicata il 13/11/2026, regole incollate; primo controllo vero su GitHub riuscito (avviato a mano alle 19:23).

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
