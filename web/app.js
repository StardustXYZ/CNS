// CNS (Chi Ni Sentimu) – app for the phone (and the PC).
// Pages are chosen by the hash (#/, #/recuperando, …), as in CNV's phone version: the
// menu stays on one line and a sideways swipe moves to the next or previous page.
// Every Google account has its own lists in Firebase (utenti/{code}/artisti); artists are
// found on Deezer. (A module: strict mode is implied.)
import { artistIdFromLink, fansLabel, getArtist, getDiscography, searchArtists } from "./deezer.js";
import { KINDS, arrange, countKinds, dateLabel, groupReleases, releaseFromApi, spotifySearchUrl } from "./discografia.js";
import { DEFAULT_KINDS, LISTENED, SKIPPED, mark, markUpTo, progress, queueOf, undoLast, unmark } from "./segnalibro.js";
import {
    addArtist, explainError, removeArtist, removeNovita, saveAllowList, saveSettings, signIn, signOutUser, startFirebase,
    updateArtist, watchAnteprime, watchArtists, watchDocument, watchNovita,
} from "./firebase.js";

const BUILD = "__BUILD__"; // replaced by app/build_site.py with the build time
const SWIPE_MIN = 70;      // px sideways to change page
const SWIPE_EDGE = 24;     // touches starting this close to the screen edge are Android's "back" gesture
const SEARCH_DELAY_MS = 350; // wait for a pause in typing before asking Deezer
const STALE_CHECK_HOURS = 9; // the check runs every 3 hours: after 9 the app warns
const DISCOGRAPHY_FRESH_HOURS = 6; // a discography saved on the phone is asked again to Deezer after this

const PAGES = [
    { path: "/", key: "controllare", label: "Controllare", render: pageControllare },
    { path: "/recuperando", key: "recuperando", label: "Recuperando", render: pageRecuperando },
    { path: "/novita", key: "novita", label: "Novità", render: pageNovita },
    { path: "/impostazioni", key: "impostazioni", label: "Impostazioni", render: pageImpostazioni },
];
const LISTS = {
    controllare: { label: "Controllare", path: "/" },
    recuperando: { label: "Recuperando", path: "/recuperando" },
    archivio: { label: "Archivio", path: "/recuperando" },
};

let swipeDirection = ""; // "next" | "prev": slide-in of the page drawn after a swipe
let installPrompt = null; // Chrome's "add to home screen", when it offers it
// Sign-in: state "loading" | "ready" | "unavailable" (Firebase did not load, e.g. offline the first time)
const account = { state: "loading", user: null, error: "", busy: false };
// What GitHub last wrote (stato/github): state "idle" | "loading" | "ok" | "error"
let github = { state: "idle", data: null, error: "" };
// The account's artists: state "idle" | "loading" | "ok" | "error"
let artists = { state: "idle", list: [], error: "" };
// The account's settings (utenti/{uid}: the ntfy topic) and its Novità (written by GitHub)
let userSettings = { state: "idle", data: {}, error: "" };
let novita = { state: "idle", list: [], error: "" };
let anteprime = { state: "idle", list: [], error: "" }; // announced releases ("In arrivo"), written by GitHub
const ntfyTest = { state: "", message: "" }; // "Manda una prova": "" | "sending" | "ok" | "error"
let ntfyDraft = null; // what is being typed in the topic box (kept when the page is redrawn)
// The allow list (config/ammessi): readable only by the administrator, who manages it from Impostazioni
let allowList = { state: "idle", data: {}, error: "" };
let allowDraft = ""; // the e-mail being typed in the "Persone ammesse" box
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_ALLOWED = 50;
const NOVITA_SEEN_KEY = "cns.novita.vista"; // when Novità was last opened on this phone (for the menu count)
const TOPIC_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
let stopWatching = [];
let copied = false; // "Copia codice" was just pressed
// Search on Deezer: state "idle" | "loading" | "ok" | "error"
const search = { query: "", state: "idle", results: [], error: "", timer: null, seq: 0 };
let actionError = ""; // a failed add/move/remove, shown on the page
let infoMessage = ""; // something done for the user (e.g. moved to Controllare at the end of a discography)
// Discographies from Deezer: artist id -> { state: "loading" | "ok" | "error", releases, savedAt, error }
const discographies = new Map();
// What the artist page shows: kind filter ("" = all) and order, per artist (default: oldest
// first in Recuperando, newest first elsewhere)
const discographyView = new Map();

// ------------------------------------------------------------------ helpers

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const pad = (n) => String(n).padStart(2, "0");
const dateTime = (d) => `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} alle ${pad(d.getHours())}:${pad(d.getMinutes())}`;
const byName = (a, b) => (a.nome || "").localeCompare(b.nome || "", "it", { sensitivity: "base" });
const savedArtist = (id) => artists.list.find((a) => a.id === String(id));
const inList = (lista) => artists.list.filter((a) => a.lista === lista).sort(byName);

function route() {
    const hash = location.hash.replace(/^#/, "") || "/";
    const [path, query] = hash.split("?");
    return { path, params: new URLSearchParams(query || "") };
}

/** The page to draw: a menu page, the search or an artist. ``tab`` is the menu entry to highlight. */
function currentView() {
    const { path, params } = route();
    if (path === "/cerca") {
        const lista = params.get("lista") === "recuperando" ? "recuperando" : "controllare";
        return { key: "cerca", tab: lista, label: "Aggiungi un artista", render: () => pageSearch(lista) };
    }
    if (path.startsWith("/artista/")) {
        const id = decodeURIComponent(path.slice("/artista/".length));
        const a = savedArtist(id);
        const tab = a?.lista === "controllare" ? "controllare" : "recuperando";
        return { key: "artista", tab: a ? tab : "controllare", label: a?.nome || "Artista", render: () => pageArtist(id) };
    }
    const page = PAGES.find((p) => p.path === path) || PAGES[0];
    return { ...page, tab: page.key };
}

function header(title, subtitle) {
    return `<div class="page-header"><h1>${esc(title)}</h1>${subtitle ? `<p class="subtitle">${esc(subtitle)}</p>` : ""}</div>`;
}

function emptyState(icon, text, note) {
    return `<p class="empty-state"><span class="big" aria-hidden="true">${icon}</span>${esc(text)}<span class="small">${esc(note)}</span></p>`;
}

function photo(src, cls = "artist-photo") {
    return src
        ? `<img class="${cls}" src="${esc(src)}" alt="" loading="lazy" referrerpolicy="no-referrer">`
        : `<span class="${cls} placeholder" aria-hidden="true">🎤</span>`;
}

/** A reminder on the list pages until the user has signed in. */
function signInHint() {
    if (account.state === "unavailable") return `<p class="notice">Sei senza connessione: le liste compariranno quando sarai online.</p>`;
    if (account.state !== "ready" || account.user) return "";
    return `<p class="notice">Per vedere e salvare le tue liste fai l'accesso con Google da <a href="#/impostazioni">Impostazioni</a>.</p>`;
}

function errorNotice() {
    if (notAllowed()) {
        return `<p class="notice notice-error">Il tuo account (${esc(account.user.email || "senza email")}) non è tra le persone ammesse a CNS.
            Chiedi a chi gestisce l'app di aggiungere questa email, poi riapri l'app.</p>`;
    }
    const text = actionError || (artists.state === "error" ? artists.error : "");
    return text ? `<p class="notice notice-error">${esc(text)}</p>` : "";
}

/** Signed in, but Firebase refuses everything: the account is not in the allow list. */
const notAllowed = () => Boolean(account.user) && artists.state === "error" && artists.code === "permission-denied";

function buildLabel() {
    if (BUILD.startsWith("__")) return "versione di prova (non pubblicata)";
    const when = new Date(BUILD);
    if (Number.isNaN(when.getTime())) return `versione ${BUILD}`;
    return `versione del ${pad(when.getDate())}/${pad(when.getMonth() + 1)}/${when.getFullYear()} ${pad(when.getHours())}:${pad(when.getMinutes())}`;
}

// ------------------------------------------------------------------ list pages

function artistCard(a) {
    let detail = a.nota ? esc(a.nota) : a.fan ? esc(fansLabel(a.fan)) : "";
    let bar = "";
    if (a.lista === "recuperando") {
        // The bookmark: how far along, and what comes next
        const { queue } = artistQueue(a);
        if (queue?.finished) detail = "Discografia finita 🎉";
        else if (queue?.next) {
            const p = progress(queue);
            detail = `${p.done} di ${p.total} · prossima: ${esc(queue.next.main.title)}`;
            bar = progressBar(p.percent);
        }
    }
    return `<a class="artist-card" href="#/artista/${esc(a.id)}">
        ${photo(a.foto)}
        <span class="artist-info"><strong>${esc(a.nome)}</strong>${detail ? `<span class="small">${detail}</span>` : ""}${bar}</span>
        <span class="chevron" aria-hidden="true">›</span></a>`;
}

function progressBar(percent) {
    return `<span class="progress" role="progressbar" aria-valuenow="${percent}" aria-valuemin="0" aria-valuemax="100"><span style="width:${percent}%"></span></span>`;
}

function infoNotice() {
    return infoMessage ? `<p class="notice">${esc(infoMessage)}</p>` : "";
}

/** Controllare and Recuperando: the artists in the list, with the button to add more. */
function listPage(lista, subtitle, icon, emptyText, emptyNote) {
    let body = "";
    if (account.user) {
        body += `<p class="page-actions"><a class="btn btn-primary" href="#/cerca?lista=${lista}">+ Aggiungi artista</a></p>`;
        const list = inList(lista);
        if (artists.state === "loading" && !artists.list.length) body += `<p class="small">Caricamento delle liste…</p>`;
        else if (list.length) body += `<div class="artist-list">${list.map(artistCard).join("")}</div>`;
        else if (artists.state !== "error") body += emptyState(icon, emptyText, emptyNote);
    } else if (account.state !== "loading") {
        body += emptyState(icon, emptyText, emptyNote);
    }
    return header(LISTS[lista].label, subtitle) + signInHint() + errorNotice() + infoNotice() + body;
}

function pageControllare() {
    return listPage("controllare", "Gli artisti con cui sei in pari: aspetti le loro uscite nuove.", "🎧",
        "Nessun artista da controllare per ora.", "Aggiungili con il pulsante qui sopra: ti arriverà una notifica a ogni uscita nuova.");
}

function pageRecuperando() {
    let page = listPage("recuperando", "Le discografie da ascoltare dall'inizio, una uscita alla volta.", "📀",
        "Nessuna discografia da recuperare per ora.", "Aggiungi gli artisti di cui vuoi ascoltare tutto, dal primo album.");
    const archived = account.user ? inList("archivio") : [];
    if (archived.length) {
        page += `<details class="archive"><summary>Archivio <span class="count">${archived.length}</span></summary>
            <div class="artist-list">${archived.map(artistCard).join("")}</div></details>`;
    }
    return page;
}

function pageNovita() {
    let body = signInHint();
    if (account.user) {
        if (novita.state === "error") body += `<p class="notice notice-error">${esc(novita.error)}</p>`;
        else if (novita.state === "loading" && !novita.list.length) body += `<p class="small">Caricamento…</p>`;
        else if (!novita.list.length) {
            body += emptyState("🔔", "Nessuna novità per ora.",
                "Quando un artista di Controllare pubblica qualcosa, la trovi qui (e ti arriva la notifica).");
        } else {
            body += `<div class="release-list">${novita.list.map(novitaRow).join("")}</div>
                <p class="page-actions"><button class="btn btn-danger" data-action="novita-clear">Svuota le Novità</button></p>`;
        }
        if (!TOPIC_PATTERN.test(userSettings.data.ntfy || "") && userSettings.state === "ok") {
            body = `<p class="notice">Per ricevere le notifiche sul telefono scrivi il tuo argomento ntfy in <a href="#/impostazioni">Impostazioni</a>.</p>` + body;
        }
        const coming = comingSoon();
        if (coming.length) {
            body = `<h2>In arrivo</h2><div class="release-list">${coming.map((n) => announcementRow(n)).join("")}</div><h2>Uscite</h2>` + body;
        }
    }
    return header("Novità", "Le uscite nuove degli artisti in Controllare, dalla più recente.") + body;
}

// ------------------------------------------------------------------ In arrivo (announced releases)

const todayIso = () => { const d = new Date(); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; };

/** The announced releases from today on (of one artist, or all), soonest first. */
function comingSoon(artistId = null) {
    const today = todayIso();
    return anteprime.list
        .filter((a) => (a.data || "") >= today && (!artistId || a.artista_id === String(artistId)))
        .sort((a, b) => (a.data || "").localeCompare(b.data || "") || (a.titolo || "").localeCompare(b.titolo || ""));
}

function daysLeftLabel(iso) {
    if (iso === todayIso()) return "esce oggi";
    const days = Math.round((new Date(`${iso}T12:00:00`) - new Date(`${todayIso()}T12:00:00`)) / 864e5);
    return days === 1 ? "esce domani" : `esce il ${dateLabel(iso)} (tra ${days} giorni)`;
}

function announcementRow(n, showArtist = true) {
    const cover = n.copertina
        ? `<img class="cover" src="${esc(n.copertina)}" alt="" loading="lazy" referrerpolicy="no-referrer">`
        : `<span class="cover placeholder" aria-hidden="true">📅</span>`;
    const isToday = n.data === todayIso();
    const artist = showArtist ? `<a href="#/artista/${esc(n.artista_id)}">${esc(n.artista)}</a> · ` : "";
    return `<div class="release coming${isToday ? " today" : ""}">${cover}
        <div class="release-info"><strong>${esc(n.titolo)}</strong>
            <span class="small">${artist}${esc(KINDS[n.tipo]?.label || "Uscita")}</span>
            <span class="when">${esc(daysLeftLabel(n.data))}</span></div>
        <div class="release-actions">
            ${isToday ? `<a class="btn btn-small btn-primary" href="${esc(n.spotify || spotifySearchUrl(n.artista, n.titolo))}" target="_blank" rel="noopener">Spotify</a>` : ""}
            ${n.link ? `<a class="btn btn-small" href="${esc(n.link)}" target="_blank" rel="noopener">Apple Music</a>` : ""}
        </div></div>`;
}

function comingSection(a) {
    const coming = comingSoon(a.id);
    if (!coming.length) return "";
    return `<h2>In arrivo</h2><div class="release-list">${coming.map((n) => announcementRow(n, false)).join("")}</div>`;
}

function novitaRow(n) {
    const cover = n.copertina
        ? `<img class="cover" src="${esc(n.copertina)}" alt="" loading="lazy" referrerpolicy="no-referrer">`
        : `<span class="cover placeholder" aria-hidden="true">💿</span>`;
    const when = n.notificata?.toDate?.();
    return `<div class="release">${cover}
        <div class="release-info"><strong>${esc(n.titolo)}</strong>
            <span class="small"><a href="#/artista/${esc(n.artista_id)}">${esc(n.artista)}</a> · ${esc(KINDS[n.tipo]?.label || "Uscita")} · ${esc(dateLabel(n.data))}</span>
            ${when ? `<span class="small">notificata il ${esc(dateTime(when))}</span>` : ""}</div>
        <div class="release-actions">
            <a class="btn btn-small btn-primary" href="${esc(n.spotify || spotifySearchUrl(n.artista, n.titolo))}" target="_blank" rel="noopener">Spotify</a>
            ${n.link ? `<a class="btn btn-small" href="${esc(n.link)}" target="_blank" rel="noopener">Deezer</a>` : ""}
        </div></div>`;
}

/** How many Novità arrived since the page was last opened on this phone. */
function unseenNovita() {
    let seen = 0;
    try { seen = Number(localStorage.getItem(NOVITA_SEEN_KEY)) || 0; } catch { /* private mode */ }
    return novita.list.filter((n) => (n.notificata?.toMillis?.() || 0) > seen).length;
}

function markNovitaSeen() {
    try { localStorage.setItem(NOVITA_SEEN_KEY, String(Date.now())); } catch { /* private mode */ }
}

// ------------------------------------------------------------------ search

function pageSearch(lista) {
    if (!account.user) return header("Aggiungi un artista") + signInHint();
    return header(`Aggiungi a ${LISTS[lista].label}`, "Cerca per nome, oppure incolla il link di un artista di Deezer.")
        + `<input type="search" id="search" value="${esc(search.query)}" placeholder="Nome dell'artista o link di Deezer"
            aria-label="Cerca un artista" autocomplete="off" enterkeyhint="search">`
        + errorNotice()
        + `<div id="results">${searchResults(lista)}</div>`
        + `<p class="page-actions"><a class="btn" href="#${LISTS[lista].path}">Fatto</a></p>`;
}

function searchResults(lista) {
    if (search.state === "idle") return `<p class="small search-hint">Ad esempio: Ava Max, Arctic Monkeys, K/DA.</p>`;
    if (search.state === "loading") return `<p class="small search-hint">Cerco su Deezer…</p>`;
    if (search.state === "error") return `<p class="error">${esc(search.error)}</p>`;
    if (!search.results.length) return `<p class="small search-hint">Nessun artista trovato.</p>`;
    return `<div class="artist-list">${search.results.map((a) => {
        const saved = savedArtist(a.id);
        let action;
        if (saved?.lista === lista) action = `<span class="badge">Già in lista ✓</span>`;
        else if (saved) action = `<button class="btn" data-action="add" data-id="${esc(a.id)}" data-lista="${lista}">Sposta qui</button>`;
        else action = `<button class="btn btn-primary" data-action="add" data-id="${esc(a.id)}" data-lista="${lista}">Aggiungi</button>`;
        const where = saved && saved.lista !== lista ? ` · in ${LISTS[saved.lista]?.label || saved.lista}` : "";
        return `<div class="artist-card">${photo(a.picture)}
            <span class="artist-info"><strong>${esc(a.name)}</strong>
            <span class="small">${esc(fansLabel(a.fans))} · ${a.albums} uscite${esc(where)}</span></span>
            ${action}</div>`;
    }).join("")}</div>`;
}

function scheduleSearch() {
    clearTimeout(search.timer);
    const query = search.query.trim();
    if (!query) {
        search.state = "idle";
        search.results = [];
        render();
        return;
    }
    search.state = "loading";
    render();
    search.timer = setTimeout(() => runSearch(query), SEARCH_DELAY_MS);
}

async function runSearch(query) {
    const seq = ++search.seq; // a slower older answer must not replace a newer one
    try {
        const id = artistIdFromLink(query);
        const results = id ? [await getArtist(id)] : await searchArtists(query);
        if (seq !== search.seq) return;
        Object.assign(search, { state: "ok", results, error: "" });
    } catch (err) {
        if (seq !== search.seq) return;
        Object.assign(search, { state: "error", results: [], error: `Ricerca non riuscita: ${err.message}. Controlla la connessione e riprova.` });
    }
    render();
}

// ------------------------------------------------------------------ artist page

function pageArtist(id) {
    const a = savedArtist(id);
    if (!a) {
        if (artists.state === "loading" || account.state === "loading") return `<p class="empty-state">Caricamento…</p>`;
        return header("Artista non trovato", "Non è tra le tue liste.") + signInHint()
            + `<p class="page-actions"><a class="btn" href="#/">Torna a Controllare</a></p>`;
    }
    const choices = Object.entries(LISTS).map(([key, { label }]) =>
        `<button class="btn segment${a.lista === key ? " active" : ""}" data-action="move" data-id="${esc(a.id)}" data-lista="${key}"
            ${a.lista === key ? 'aria-pressed="true"' : 'aria-pressed="false"'}>${label}</button>`).join("");
    return `<div class="artist-hero">${photo(a.foto, "artist-photo big")}
            <div><h1>${esc(a.nome)}</h1>${a.fan ? `<p class="subtitle">${esc(fansLabel(a.fan))}</p>` : ""}
            ${a.link ? `<p class="card-action"><a class="btn" href="${esc(a.link)}" target="_blank" rel="noopener">Apri su Deezer</a></p>` : ""}</div>
        </div>
        ${errorNotice()}${infoNotice()}
        ${a.lista === "recuperando" ? bookmarkSection(a) : ""}
        ${comingSection(a)}
        ${a.lista === "controllare" ? alertsSection(a) : ""}
        <h2>Lista</h2>
        <div class="segmented" role="group" aria-label="Lista">${choices}</div>
        <h2>Nota</h2>
        <textarea id="nota" data-id="${esc(a.id)}" maxlength="500" rows="3" placeholder="Ad esempio: aspetto il nuovo album">${esc(a.nota || "")}</textarea>
        <p class="small">La nota si salva da sola quando esci dalla casella.</p>
        ${discographySection(a)}
        <p class="page-actions"><button class="btn btn-danger" data-action="remove" data-id="${esc(a.id)}">Togli dalle liste</button></p>`;
}

// ------------------------------------------------------------------ discography

const cacheKey = (id) => `cns.discografia.${id}`;

function readSavedDiscography(id) {
    try {
        const saved = JSON.parse(localStorage.getItem(cacheKey(id)));
        return saved && Array.isArray(saved.releases) ? saved : null;
    } catch {
        return null;
    }
}

function saveDiscography(id, releases, savedAt) {
    try {
        localStorage.setItem(cacheKey(id), JSON.stringify({ releases, savedAt }));
    } catch { /* full or private mode: it is just asked again next time */ }
}

/** The artist's discography: the copy on the phone at once, then Deezer if the copy is old or missing. */
function ensureDiscography(id, force = false) {
    let entry = discographies.get(id);
    if (!entry) {
        const saved = readSavedDiscography(id);
        entry = saved ? { state: "ok", releases: saved.releases, savedAt: saved.savedAt, error: "" } : { state: "idle", releases: [], savedAt: null, error: "" };
        discographies.set(id, entry);
    }
    const fresh = entry.savedAt && Date.now() - new Date(entry.savedAt).getTime() < DISCOGRAPHY_FRESH_HOURS * 36e5;
    const justFailed = entry.failedAt && Date.now() - entry.failedAt < 60 * 1000; // no retry loop when Deezer is down
    if (entry.loading || ((fresh || justFailed) && !force)) return entry;
    entry.loading = true;
    if (!entry.releases.length) entry.state = "loading";
    getDiscography(id).then((items) => {
        const releases = items.map(releaseFromApi);
        const savedAt = new Date().toISOString();
        Object.assign(entry, { state: "ok", releases, savedAt, error: "", loading: false, failedAt: 0 });
        saveDiscography(id, releases, savedAt);
    }).catch((err) => {
        // With a saved copy, keep showing it; otherwise explain
        Object.assign(entry, { state: entry.releases.length ? "ok" : "error", error: err.message, loading: false, failedAt: Date.now() });
    }).finally(() => {
        // Redraw where this discography is shown: its artist page, or the Recuperando list (progress)
        const view = currentView().key;
        if (view === "recuperando" || (view === "artista" && decodeURIComponent(route().path.slice("/artista/".length)) === id)) render();
    });
    return entry;
}

function viewOf(a) {
    return discographyView.get(a.id) || { kind: "", oldestFirst: a.lista === "recuperando" };
}

function discographySection(a) {
    const entry = ensureDiscography(a.id);
    let body;
    if (entry.state === "loading" || entry.state === "idle") {
        body = `<p class="small">Carico la discografia da Deezer…</p>`;
    } else if (entry.state === "error") {
        body = `<p class="error">Discografia non caricata: ${esc(entry.error)}.</p>
            <p class="card-action"><button class="btn" data-action="disco-reload" data-id="${esc(a.id)}">Riprova</button></p>`;
    } else {
        const groups = groupReleases(entry.releases, a.nome);
        const counts = countKinds(groups);
        const view = viewOf(a);
        const kind = counts[view.kind] ? view.kind : "";
        const chip = (key, label, n) => `<button class="chip${kind === key ? " active" : ""}" data-action="disco-kind" data-id="${esc(a.id)}" data-kind="${key}"
            aria-pressed="${kind === key}">${esc(label)} <span class="count">${n}</span></button>`;
        const chips = [chip("", "Tutte", groups.length),
            ...Object.entries(KINDS).filter(([key]) => counts[key]).map(([key, k]) => chip(key, k.plural, counts[key]))].join("");
        const queue = a.lista === "recuperando" ? queueOf(groups, a.fatte || {}, kindsOf(a)) : null;
        const rows = arrange(groups, kind, view.oldestFirst).map((g) => releaseRow(a, g, queue)).join("");
        const saved = entry.savedAt ? new Date(entry.savedAt) : null;
        const offline = entry.error ? ` · <span class="warn">Deezer non risponde: è la copia salvata</span>` : "";
        body = `<div class="chips" role="group" aria-label="Tipo di uscita">${chips}</div>
            <p class="disco-tools">
                <button class="btn btn-small" data-action="disco-order" data-id="${esc(a.id)}">${view.oldestFirst ? "↑ Dalla più vecchia" : "↓ Dalla più recente"}</button>
                <span class="small">${saved ? `aggiornata il ${esc(dateTime(saved))}` : ""}${offline}</span>
            </p>
            ${rows ? `<div class="release-list">${rows}</div>` : `<p class="small">Nessuna uscita su Deezer.</p>`}`;
    }
    return `<h2>Discografia</h2>${body}`;
}

/** In Recuperando, each release of the queue says whether it was listened to, with the button to change it. */
function bookmarkMark(a, g, queue) {
    if (!queue || !queue.all.includes(g)) return "";
    const done = (a.fatte || {})[g.key];
    const id = esc(a.id), key = esc(g.key);
    if (done) {
        const label = done.s === SKIPPED ? "Saltato" : "✓ Ascoltato";
        return `<span class="mark-row"><span class="badge${done.s === SKIPPED ? " skipped" : ""}">${label}</span>
            <button class="link-button" data-action="bm-unmark" data-id="${id}" data-key="${key}">annulla</button></span>`;
    }
    return `<span class="mark-row"><button class="link-button" data-action="bm-upto" data-id="${id}" data-key="${key}">Arrivato qui</button></span>`;
}

function releaseRow(a, g, queue = null) {
    const r = g.main;
    const cover = r.cover
        ? `<img class="cover" src="${esc(r.cover)}" alt="" loading="lazy" referrerpolicy="no-referrer">`
        : `<span class="cover placeholder" aria-hidden="true">💿</span>`;
    const versions = g.versions.length
        ? `<details class="versions"><summary>+${g.versions.length} ${g.versions.length === 1 ? "versione" : "versioni"}</summary><ul>${g.versions.map((v) =>
            `<li><a href="${esc(v.link)}" target="_blank" rel="noopener">${esc(v.title)}</a> <span class="small">· ${esc(dateLabel(v.date))}</span></li>`).join("")}</ul></details>`
        : "";
    return `<div class="release">${cover}
        <div class="release-info"><strong>${esc(r.title)}</strong>
            <span class="small">${esc(KINDS[g.kind].label)} · ${esc(dateLabel(g.date))}${r.explicit ? " · 🅴" : ""}</span>${versions}${bookmarkMark(a, g, queue)}</div>
        <div class="release-actions">
            <a class="btn btn-small btn-primary" href="${esc(spotifySearchUrl(a.nome, r.title))}" target="_blank" rel="noopener">Spotify</a>
            <a class="btn btn-small" href="${esc(r.link)}" target="_blank" rel="noopener">Deezer</a>
        </div></div>`;
}

function discographyAction(button) {
    const a = savedArtist(button.dataset.id);
    if (!a) return;
    const view = { ...viewOf(a) };
    if (button.dataset.action === "disco-kind") view.kind = button.dataset.kind;
    if (button.dataset.action === "disco-order") view.oldestFirst = !view.oldestFirst;
    if (button.dataset.action === "disco-reload") {
        ensureDiscography(a.id, true);
    }
    discographyView.set(a.id, view);
    render();
}

// ------------------------------------------------------------------ bookmark (Recuperando)

/** The kinds this artist's catch-up includes (saved per artist; compilations are out by default). */
const kindsOf = (a) => (Array.isArray(a.tipi_recupero) && a.tipi_recupero.length ? a.tipi_recupero : DEFAULT_KINDS);

/** The artist's discography as a queue (null while it is not loaded). */
function artistQueue(a) {
    const entry = ensureDiscography(a.id);
    if (entry.state !== "ok") return { entry, queue: null };
    return { entry, queue: queueOf(groupReleases(entry.releases, a.nome), a.fatte || {}, kindsOf(a)) };
}

function bookmarkSection(a) {
    const { entry, queue } = artistQueue(a);
    const id = esc(a.id);
    let body;
    if (!queue) {
        body = entry.state === "error"
            ? `<p class="error">Discografia non caricata: il segnalibro tornerà quando Deezer risponde.</p>`
            : `<p class="small">Carico la discografia da Deezer…</p>`;
    } else if (!queue.total) {
        body = `<p class="small">Nessuna uscita da recuperare con i tipi scelti qui sotto.</p>`;
    } else if (queue.finished) {
        const undo = `<button class="link-button" data-action="bm-undo" data-id="${id}">↶ Annulla l'ultimo</button>`;
        body = a.fine_tenuta
            ? `<div class="card bookmark"><p><strong>Discografia finita 🎉</strong></p>
                <p class="small">Resta in Recuperando: le uscite nuove compariranno qui, in fondo alla coda.</p>${undo}</div>`
            : `<div class="card bookmark"><p><strong>Hai finito la discografia di ${esc(a.nome)} 🎉</strong></p>
                <p class="small">Cosa ne facciamo?</p>
                <p class="card-action button-row">
                    <button class="btn btn-primary" data-action="bm-end" data-id="${id}" data-choice="controllare">Sposta in Controllare</button>
                    <button class="btn" data-action="bm-end" data-id="${id}" data-choice="tieni">Tieni qui</button>
                    <button class="btn" data-action="bm-end" data-id="${id}" data-choice="archivio">Archivia</button>
                </p>${undo}</div>`;
    } else {
        const g = queue.next;
        const r = g.main;
        const p = progress(queue);
        const cover = r.cover
            ? `<img class="cover" src="${esc(r.cover)}" alt="" loading="lazy" referrerpolicy="no-referrer">`
            : `<span class="cover placeholder" aria-hidden="true">💿</span>`;
        body = `<div class="card bookmark">
            <p class="small">Prossima da ascoltare</p>
            <div class="release next">${cover}
                <div class="release-info"><strong>${esc(r.title)}</strong>
                    <span class="small">${esc(KINDS[g.kind].label)} · ${esc(dateLabel(g.date))}</span></div>
                <div class="release-actions">
                    <a class="btn btn-small btn-primary" href="${esc(spotifySearchUrl(a.nome, r.title))}" target="_blank" rel="noopener">Spotify</a>
                    <a class="btn btn-small" href="${esc(r.link)}" target="_blank" rel="noopener">Deezer</a>
                </div></div>
            <p class="card-action button-row">
                <button class="btn btn-primary" data-action="bm-listened" data-id="${id}" data-key="${esc(g.key)}">✓ Ascoltato</button>
                <button class="btn" data-action="bm-skip" data-id="${id}" data-key="${esc(g.key)}">Salta</button>
                ${Object.keys(a.fatte || {}).length ? `<button class="btn" data-action="bm-undo" data-id="${id}">↶ Annulla l'ultimo</button>` : ""}
            </p>
            ${progressBar(p.percent)}
            <p class="small">${p.done} di ${p.total} (${p.percent}%) · ascoltate ${queue.listened}, saltate ${queue.skipped}</p>
        </div>`;
    }
    const kinds = kindsOf(a);
    const kindChips = Object.entries(KINDS).map(([key, k]) =>
        `<button class="chip${kinds.includes(key) ? " active" : ""}" data-action="bm-kind" data-id="${id}" data-kind="${key}" aria-pressed="${kinds.includes(key)}">${esc(k.plural)}</button>`).join("");
    return `<h2>Segnalibro</h2>${body}
        <details class="bookmark-settings"><summary>Cosa recuperare e cosa fare alla fine</summary>
            <div class="chips" role="group" aria-label="Tipi da recuperare">${kindChips}</div>
            <label class="check"><input type="checkbox" data-action="bm-auto" data-id="${id}"${a.auto_sposta ? " checked" : ""}>
                Quando finisco, sposta in automatico in Controllare</label>
            <p class="small">Per partire da dove sei arrivato, tocca «Arrivato qui» su un'uscita della discografia qui sotto.</p>
        </details>`;
}

/** Ascoltato, Salta, Annulla, Arrivato qui, tipi, fine della discografia: saved in the artist's document. */
async function bookmarkAction(target) {
    const uid = account.user?.uid;
    const a = savedArtist(target.dataset.id);
    if (!uid || !a) return;
    const { action, key, kind, choice } = target.dataset;
    actionError = "";
    infoMessage = "";
    const fatte = a.fatte || {};
    const fields = {};
    if (action === "bm-listened") fields.fatte = mark(fatte, key, LISTENED);
    else if (action === "bm-skip") fields.fatte = mark(fatte, key, SKIPPED);
    else if (action === "bm-undo") fields.fatte = undoLast(fatte).fatte;
    else if (action === "bm-unmark") fields.fatte = unmark(fatte, key);
    else if (action === "bm-upto") {
        const { queue } = artistQueue(a);
        if (queue) fields.fatte = markUpTo(queue.all, key, fatte);
    } else if (action === "bm-kind") {
        const kinds = kindsOf(a);
        const next = kinds.includes(kind) ? kinds.filter((k) => k !== kind) : [...kinds, kind];
        if (!next.length) return; // at least one kind
        fields.tipi_recupero = next;
    } else if (action === "bm-auto") {
        fields.auto_sposta = target.checked;
    } else if (action === "bm-end") {
        if (choice === "tieni") fields.fine_tenuta = true;
        else {
            fields.lista = choice;
            fields.fine_tenuta = false;
            infoMessage = `${a.nome} è passato in ${LISTS[choice].label}.`;
        }
    }
    if (!Object.keys(fields).length) return;
    // Just finished: with "sposta in automatico" the artist goes to Controllare at once
    if (fields.fatte && a.auto_sposta) {
        const { queue } = artistQueue({ ...a, fatte: fields.fatte });
        if (queue?.finished) {
            fields.lista = "controllare";
            infoMessage = `Discografia finita: ${a.nome} è passato in Controllare.`;
        }
    }
    try {
        await updateArtist(uid, a.id, fields);
    } catch (err) {
        actionError = explainError(err);
        infoMessage = "";
    }
    render();
}

// ------------------------------------------------------------------ alerts (Controllare)

/** The kinds of release this person is told about for this artist (all, unless changed). */
const alertKindsOf = (a) => (Array.isArray(a.tipi_avviso) && a.tipi_avviso.length ? a.tipi_avviso : Object.keys(KINDS));

function alertsSection(a) {
    const kinds = alertKindsOf(a);
    const chips = Object.entries(KINDS).map(([key, k]) =>
        `<button class="chip${kinds.includes(key) ? " active" : ""}" data-action="alert-kind" data-id="${esc(a.id)}" data-kind="${key}" aria-pressed="${kinds.includes(key)}">${esc(k.plural)}</button>`).join("");
    return `<h2>Avvisi</h2>
        <div class="chips" role="group" aria-label="Tipi di uscita da segnalare">${chips}</div>
        <p class="small">Ti arriva una notifica quando ${esc(a.nome)} pubblica un'uscita di questi tipi.</p>`;
}

async function alertAction(button) {
    const uid = account.user?.uid;
    const a = savedArtist(button.dataset.id);
    if (!uid || !a) return;
    const kinds = alertKindsOf(a);
    const kind = button.dataset.kind;
    const next = kinds.includes(kind) ? kinds.filter((k) => k !== kind) : [...kinds, kind];
    if (!next.length) return; // at least one kind: to get none, move the artist to Recuperando or Archivio
    actionError = "";
    try {
        await updateArtist(uid, a.id, { tipi_avviso: next });
    } catch (err) {
        actionError = explainError(err);
        render();
    }
}

// ------------------------------------------------------------------ notifications (Impostazioni)

function ntfyCard() {
    if (!account.user) return "";
    const saved = userSettings.data.ntfy || "";
    const topic = ntfyDraft ?? saved;
    const status = ntfyTest.state === "sending" ? `<p class="small">Invio…</p>`
        : ntfyTest.state === "ok" ? `<p class="badge">${esc(ntfyTest.message)}</p>`
        : ntfyTest.state === "error" ? `<p class="error">${esc(ntfyTest.message)}</p>` : "";
    return `<div class="card">
        <label for="ntfy-topic"><strong>Argomento ntfy</strong></label>
        <p class="small">Il nome dell'argomento a cui è iscritta l'app ntfy sul tuo telefono (solo il nome, senza https://ntfy.sh/). Chi lo conosce può leggere le tue notifiche: tienilo lungo e casuale.</p>
        <input type="text" id="ntfy-topic" value="${esc(topic)}" placeholder="ad esempio cns-x7Kp2…" autocomplete="off" autocapitalize="off" spellcheck="false" maxlength="64">
        <p class="card-action button-row">
            <button class="btn btn-primary" data-action="ntfy-save">Salva</button>
            <button class="btn" data-action="ntfy-test"${TOPIC_PATTERN.test(saved) && topic === saved ? "" : " disabled"}>Manda una prova</button>
        </p>${status}</div>`;
}

async function ntfyAction(action) {
    const uid = account.user?.uid;
    if (!uid) return;
    const box = document.getElementById("ntfy-topic");
    if (action === "ntfy-save") {
        const topic = (ntfyDraft ?? box?.value ?? "").trim().replace(/^https?:\/\/ntfy\.sh\//, "");
        if (topic && !TOPIC_PATTERN.test(topic)) {
            Object.assign(ntfyTest, { state: "error", message: "Solo lettere, cifre, - e _ (massimo 64)." });
            render();
            return;
        }
        try {
            await saveSettings(uid, { ntfy: topic });
            ntfyDraft = null;
            Object.assign(ntfyTest,{ state: "ok", message: topic ? "Salvato ✓" : "Argomento tolto: le uscite nuove resteranno solo in Novità." });
        } catch (err) {
            Object.assign(ntfyTest, { state: "error", message: explainError(err) });
        }
        box?.blur();
        render();
        return;
    }
    // "Manda una prova": straight from the phone to ntfy, as GitHub will do
    Object.assign(ntfyTest, { state: "sending", message: "" });
    render();
    try {
        const resp = await fetch("https://ntfy.sh/", {
            method: "POST",
            body: JSON.stringify({
                topic: userSettings.data.ntfy, title: "CNS", tags: ["headphones"],
                message: "Le notifiche funzionano: ti scrivo quando un artista di Controllare pubblica qualcosa.",
            }),
        });
        if (!resp.ok) throw new Error(`ntfy ha risposto ${resp.status}`);
        Object.assign(ntfyTest, { state: "ok", message: "Prova inviata: controlla il telefono ✓" });
    } catch (err) {
        Object.assign(ntfyTest, { state: "error", message: `Prova non inviata: ${err.message}` });
    }
    render();
}

async function clearNovita() {
    const uid = account.user?.uid;
    if (!uid || !novita.list.length) return;
    if (!confirm(`Cancellare tutte le ${novita.list.length} Novità? Le uscite restano nella discografia degli artisti.`)) return;
    try {
        await removeNovita(uid, novita.list.map((n) => n.id));
    } catch (err) {
        novita.error = explainError(err);
        render();
    }
}

// ------------------------------------------------------------------ account (Impostazioni)

// ------------------------------------------------------------------ allow list (administrator only)

const isAdmin = () => allowList.state === "ok" && allowList.data.admin === account.user?.uid;

function allowListCard() {
    if (!isAdmin()) return "";
    const emails = Array.isArray(allowList.data.email) ? allowList.data.email : [];
    const rows = emails.length
        ? `<ul class="allow-list">${emails.map((e) => `<li><span>${esc(e)}</span>
            <button class="link-button" data-action="allow-remove" data-email="${esc(e)}">togli</button></li>`).join("")}</ul>`
        : `<p class="small">Per ora entri solo tu.</p>`;
    const error = allowList.error ? `<p class="error">${esc(allowList.error)}</p>` : "";
    return `<div class="card"><p><strong>Persone ammesse</strong></p>
        <p class="small">Solo tu (l'amministratore) e queste email Google possono usare CNS; ognuno vede solo le sue liste.</p>
        ${rows}
        <input type="text" id="allow-email" value="${esc(allowDraft)}" placeholder="email@gmail.com" inputmode="email" autocomplete="off" autocapitalize="off" spellcheck="false">
        <p class="card-action"><button class="btn btn-primary" data-action="allow-add"${emails.length >= MAX_ALLOWED ? " disabled" : ""}>Aggiungi</button></p>
        ${error}</div>`;
}

async function allowListAction(button) {
    const emails = Array.isArray(allowList.data.email) ? allowList.data.email : [];
    allowList.error = "";
    let next;
    if (button.dataset.action === "allow-add") {
        const email = allowDraft.trim().toLowerCase();
        if (!EMAIL_PATTERN.test(email)) {
            allowList.error = "Scrivi un indirizzo email valido.";
            render();
            return;
        }
        if (emails.includes(email)) {
            allowList.error = "Questa email è già nella lista.";
            render();
            return;
        }
        next = [...emails, email];
    } else {
        const email = button.dataset.email;
        if (!confirm(`Togliere ${email}? Non potrà più usare CNS (le sue liste restano salvate).`)) return;
        next = emails.filter((e) => e !== email);
    }
    try {
        await saveAllowList(next);
        allowDraft = "";
    } catch (err) {
        allowList.error = explainError(err);
    }
    render();
}

function pageImpostazioni() {
    const install = installPrompt
        ? `<p class="card-action"><button class="btn btn-primary" data-action="install">Aggiungi alla schermata Home</button></p>`
        : "";
    return header("Impostazioni", "Il tuo account, le notifiche e l'app.")
        + `<h2>Account</h2>${accountCard()}${githubCard()}${allowListCard()}
        <h2>Notifiche</h2>
        ${ntfyCard()}
        <div class="card"><ul class="settings-list">
            <li><span>Controllo delle uscite</span><span class="value">ogni 3 ore</span></li>
            <li><span>Per chi</span><span class="value">gli artisti in Controllare</span></li>
            <li><span>Di notte</span><span class="value">dalle 23 alle 8 senza suono</span></li>
            <li><span>Più di 3 uscite insieme</span><span class="value">una notifica sola</span></li>
            <li><span>Tipi di uscita</span><span class="value">tutti; si cambiano nella pagina dell'artista</span></li>
            <li><span>Artista appena aggiunto</span><span class="value">la prima volta nessun avviso</span></li>
        </ul></div>
        <h2>App</h2>
        <div class="card"><ul class="settings-list">
            <li><span>Versione</span><span class="value">${esc(buildLabel())}</span></li>
            <li><span>Dati delle uscite</span><span class="value">Deezer</span></li>
        </ul>${install}</div>`;
}

function accountCard() {
    if (account.state === "loading") return `<div class="card"><p class="small">Controllo dell'accesso…</p></div>`;
    if (account.state === "unavailable") {
        return `<div class="card"><p>Firebase non si è caricato: forse sei senza connessione.</p>
            <p class="small">Riapri l'app quando sei online per accedere e vedere le tue liste.</p></div>`;
    }
    const error = account.error ? `<p class="error">${esc(account.error)}</p>` : "";
    const disabled = account.busy ? " disabled" : "";
    if (!account.user) {
        return `<div class="card"><p>Accedi con il tuo account Google: le tue liste vengono salvate su Firebase e solo tu puoi vederle.</p>
            ${error}<p class="card-action"><button class="btn btn-primary" data-action="sign-in"${disabled}>Accedi con Google</button></p></div>`;
    }
    const u = account.user;
    return `<div class="card"><ul class="settings-list">
            <li><span>Accesso fatto come</span><span class="value">${esc(u.name || u.email)}</span></li>
            ${u.name && u.email ? `<li><span>Email</span><span class="value">${esc(u.email)}</span></li>` : ""}
            <li><span>Codice utente</span><span class="value"><code class="uid">${esc(u.uid)}</code></span></li>
        </ul>
        <p class="small">Le tue liste sono nel tuo spazio personale su Firebase: nessun altro account può vederle.</p>
        ${error}<p class="card-action button-row">
            <button class="btn" data-action="copy-uid">${copied ? "Copiato ✓" : "Copia codice"}</button>
            <button class="btn" data-action="sign-out"${disabled}>Esci</button>
        </p></div>`;
}

function githubCard() {
    if (!account.user) return "";
    let text;
    if (github.state === "loading") text = `<span class="small">lettura…</span>`;
    else if (github.state === "error") text = `<span class="error">${esc(github.error)}</span>`;
    else if (!github.data) text = "mai finora";
    else {
        const when = github.data.ultimo_contatto?.toDate?.();
        text = when ? esc(dateTime(when)) : "data sconosciuta";
        // Three runs in a row missing (GitHub can be hours late, but not this much)
        if (when && Date.now() - when.getTime() > STALE_CHECK_HOURS * 36e5) {
            text += `<br><span class="warn">in ritardo: GitHub non controlla da più di ${STALE_CHECK_HOURS} ore</span>`;
        }
    }
    return `<div class="card"><ul class="settings-list">
        <li><span>Ultimo controllo da GitHub</span><span class="value">${text}</span></li>
    </ul><p class="small">Il controllo parte da solo ogni 3 ore, anche con il telefono e il PC spenti.</p></div>`;
}

// ------------------------------------------------------------------ Firebase

/** Follow what belongs to the signed-in account (its artists, GitHub's status); stop when signing out. */
function followAccount() {
    stopWatching.forEach((stop) => stop());
    stopWatching = [];
    const uid = account.user?.uid;
    github = { state: uid ? "loading" : "idle", data: null, error: "" };
    artists = { state: uid ? "loading" : "idle", list: [], error: "" };
    userSettings = { state: uid ? "loading" : "idle", data: {}, error: "" };
    novita = { state: uid ? "loading" : "idle", list: [], error: "" };
    anteprime = { state: uid ? "loading" : "idle", list: [], error: "" };
    allowList = { state: "idle", data: {}, error: "" };
    if (!uid) return;
    stopWatching.push(watchDocument(`utenti/${uid}`,
        (data) => {
            userSettings = { state: "ok", data: data || {}, error: "" };
            // The e-mail goes with the settings: the check on GitHub uses it to skip people no longer admitted
            const email = (account.user?.email || "").toLowerCase();
            if (email && userSettings.data.email !== email) saveSettings(uid, { email }).catch(() => { /* not admitted */ });
            render();
        },
        (err) => { userSettings = { state: "error", data: {}, error: explainError(err) }; render(); }));
    stopWatching.push(watchAnteprime(uid,
        (list) => { anteprime = { state: "ok", list, error: "" }; render(); },
        (err) => { anteprime = { state: "error", list: [], error: explainError(err) }; render(); }));
    stopWatching.push(watchNovita(uid,
        (list) => { novita = { state: "ok", list, error: "" }; if (currentView().key === "novita") markNovitaSeen(); render(); },
        (err) => { novita = { state: "error", list: [], error: explainError(err) }; render(); }));
    stopWatching.push(watchDocument("stato/github",
        (data) => { github = { state: "ok", data, error: "" }; render(); },
        (err) => { github = { state: "error", data: null, error: explainError(err) }; render(); }));
    stopWatching.push(watchArtists(uid,
        (list) => { artists = { state: "ok", list, error: "" }; render(); },
        (err) => { artists = { state: "error", list: [], error: explainError(err), code: err?.code || "" }; render(); }));
    // Only the administrator can read the allow list: for everybody else this is refused, and that is fine
    stopWatching.push(watchDocument("config/ammessi",
        (data) => { allowList = { state: "ok", data: data || {}, error: "" }; render(); },
        () => { allowList = { state: "none", data: {}, error: "" }; render(); }));
}

async function accountAction(action) {
    account.error = "";
    if (action === "copy-uid") {
        try {
            await navigator.clipboard.writeText(account.user.uid);
            copied = true;
            setTimeout(() => { copied = false; render(); }, 2000);
        } catch {
            account.error = "Non riesco a copiare: tieni premuto sul codice per selezionarlo.";
        }
        render();
        return;
    }
    account.busy = true;
    render();
    try {
        await (action === "sign-in" ? signIn() : signOutUser());
    } catch (err) {
        account.error = explainError(err);
    }
    account.busy = false;
    render();
}

/** Add, move or remove an artist. Firestore keeps the change on the phone if offline and sends it later. */
async function artistAction(button) {
    const { action, id, lista } = button.dataset;
    const uid = account.user?.uid;
    if (!uid) return;
    actionError = "";
    try {
        if (action === "add") {
            const found = search.results.find((a) => a.id === id);
            if (savedArtist(id)) await updateArtist(uid, id, { lista });
            else if (found) await addArtist(uid, found, lista);
        } else if (action === "move") {
            await updateArtist(uid, id, { lista });
        } else if (action === "remove") {
            const a = savedArtist(id);
            if (!confirm(`Togliere ${a?.nome || "questo artista"} dalle tue liste? La nota andrà persa.`)) return;
            const back = LISTS[a?.lista]?.path || "/";
            await removeArtist(uid, id);
            location.hash = `#${back}`;
        }
    } catch (err) {
        actionError = explainError(err);
        render();
    }
}

async function saveNote(textarea) {
    const uid = account.user?.uid;
    const a = savedArtist(textarea.dataset.id);
    const nota = textarea.value.trim().slice(0, 500);
    if (!uid || !a || (a.nota || "") === nota) return;
    try {
        await updateArtist(uid, a.id, { nota });
    } catch (err) {
        actionError = explainError(err);
        render();
    }
}

// ------------------------------------------------------------------ rendering

function render() {
    const view = currentView();
    const app = document.getElementById("app");
    const typing = document.activeElement;
    if (typing?.id === "search" && view.key === "cerca" && app.querySelector("#results")) {
        // Typing a search: redraw only the results, so the box keeps the focus and the keyboard
        app.querySelector("#results").innerHTML = searchResults(route().params.get("lista") === "recuperando" ? "recuperando" : "controllare");
    } else if ((typing?.id === "nota" && view.key === "artista") || (["ntfy-topic", "allow-email"].includes(typing?.id) && view.key === "impostazioni")) {
        // Writing in a box: leave the page as it is until the box is left
    } else {
        app.innerHTML = view.render();
        if (swipeDirection) {
            app.classList.remove("swipe-next", "swipe-prev");
            void app.offsetWidth; // restart the animation
            app.classList.add(`swipe-${swipeDirection}`);
            swipeDirection = "";
        }
    }
    document.title = `${view.label} – CNS`;
    renderNav(view.tab);
}

function renderNav(active) {
    if (active === "novita") markNovitaSeen();
    const counts = account.user
        ? { controllare: inList("controllare").length, recuperando: inList("recuperando").length, novita: unseenNovita() }
        : {};
    const nav = document.getElementById("nav-links");
    nav.innerHTML = PAGES.map((p) => {
        const n = counts[p.key];
        return `<a href="#${p.path}" class="${active === p.key ? "active" : ""}"${active === p.key ? ' aria-current="page"' : ""}>${esc(p.label)}${n ? ` <span class="count">${n}</span>` : ""}</a>`;
    }).join("");
    // The menu scrolls sideways on narrow screens: keep the current page in view
    const current = nav.querySelector("a.active");
    if (current) nav.scrollLeft = Math.max(0, current.offsetLeft - nav.offsetLeft - (nav.clientWidth - current.offsetWidth) / 2);
}

// ------------------------------------------------------------------ events

window.addEventListener("hashchange", () => {
    actionError = "";
    infoMessage = "";
    const { path, params } = route();
    if (path === "/cerca" && params.get("q") === null && document.activeElement?.id !== "search") {
        // A new search starts empty
        Object.assign(search, { query: "", state: "idle", results: [], error: "" });
    }
    render();
    window.scrollTo(0, 0);
    if (path === "/cerca") document.getElementById("search")?.focus();
});

document.addEventListener("click", (e) => {
    const button = e.target.closest("[data-action]");
    if (!button) return;
    const action = button.dataset.action;
    if (["sign-in", "sign-out", "copy-uid"].includes(action)) accountAction(action);
    if (["add", "move", "remove"].includes(action)) artistAction(button);
    if (["disco-kind", "disco-order", "disco-reload"].includes(action)) discographyAction(button);
    if (action.startsWith("bm-") && action !== "bm-auto") bookmarkAction(button);
    if (action === "alert-kind") alertAction(button);
    if (action === "ntfy-save" || action === "ntfy-test") ntfyAction(action);
    if (action === "allow-add" || action === "allow-remove") allowListAction(button);
    if (action === "novita-clear") clearNovita();
    if (action === "install" && installPrompt) {
        installPrompt.prompt();
        installPrompt.userChoice.finally(() => { installPrompt = null; render(); });
    }
});

document.addEventListener("input", (e) => {
    if (e.target.id === "ntfy-topic") ntfyDraft = e.target.value;
    if (e.target.id === "allow-email") allowDraft = e.target.value;
    if (e.target.id !== "search") return;
    search.query = e.target.value;
    scheduleSearch();
});

document.addEventListener("change", (e) => {
    if (e.target.id === "nota") saveNote(e.target);
    if (e.target.dataset.action === "bm-auto") bookmarkAction(e.target);
});

document.addEventListener("focusout", (e) => {
    // After leaving the note box, draw the page again with what was saved
    if (["nota", "ntfy-topic", "allow-email"].includes(e.target.id)) setTimeout(render, 0);
});

window.addEventListener("beforeinstallprompt", (e) => {
    e.preventDefault(); // shown as a button in Impostazioni instead of Chrome's banner
    installPrompt = e;
    if (currentView().key === "impostazioni") render();
});

// ------------------------------------------------------------------ swipe between pages

let swipe = null; // the touch in progress: {x, y, horizontal}

/** The menu page a swipe leads to (step +1 = next, -1 = previous), or null at the ends and off the menu. */
function swipeTarget(step) {
    const index = PAGES.findIndex((p) => p.path === route().path || (p.path === "/" && route().path === ""));
    const target = index === -1 ? null : PAGES[index + step];
    return target ? `#${target.path}` : null;
}

function endSwipe() {
    swipe = null;
    const app = document.getElementById("app");
    app.style.transition = "";
    app.style.transform = "";
}

document.addEventListener("touchstart", (e) => {
    swipe = null;
    if (e.touches.length !== 1) return;
    const t = e.touches[0];
    if (t.clientX < SWIPE_EDGE || t.clientX > window.innerWidth - SWIPE_EDGE) return;
    if (e.target.closest(".nav-links, .segmented, .chips, input, select, textarea")) return; // they scroll or type by themselves
    swipe = { x: t.clientX, y: t.clientY, horizontal: null };
}, { passive: true });

document.addEventListener("touchmove", (e) => {
    if (!swipe) return;
    const dx = e.touches[0].clientX - swipe.x;
    const dy = e.touches[0].clientY - swipe.y;
    // Decide once, after a few px: sideways = swipe, otherwise the page is just scrolling
    if (swipe.horizontal === null && Math.hypot(dx, dy) > 12) swipe.horizontal = Math.abs(dx) > Math.abs(dy) * 1.5;
    if (swipe.horizontal && swipeTarget(dx < 0 ? 1 : -1)) {
        const app = document.getElementById("app");
        app.style.transition = "none";
        app.style.transform = `translateX(${dx / 4}px)`; // the page follows the finger a little
    }
}, { passive: true });

document.addEventListener("touchend", (e) => {
    if (!swipe) return;
    const dx = e.changedTouches[0].clientX - swipe.x;
    const horizontal = swipe.horizontal;
    endSwipe();
    if (!horizontal || Math.abs(dx) < SWIPE_MIN) return;
    const step = dx < 0 ? 1 : -1; // finger to the left: next page
    const target = swipeTarget(step);
    if (!target) return;
    swipeDirection = step > 0 ? "next" : "prev";
    location.hash = target;
});
document.addEventListener("touchcancel", endSwipe);
// The slide-in class goes away once played, so a later redraw never starts from an old animation
document.getElementById("app").addEventListener("animationend", (e) => e.currentTarget.classList.remove("swipe-next", "swipe-prev"));

// ------------------------------------------------------------------ start

document.getElementById("version").textContent = buildLabel();
render();

startFirebase((user) => {
    account.state = "ready";
    account.user = user;
    followAccount();
    render();
}).catch(() => {
    account.state = "unavailable";
    render();
});

if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("sw.js").catch(() => { /* works without, just not offline */ });
}
