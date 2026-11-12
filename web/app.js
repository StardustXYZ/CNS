// CNS (Chi Ni Sentimu) – app for the phone (and the PC).
// Pages are chosen by the hash (#/, #/recuperando, …), as in CNV's phone version: the
// menu stays on one line and a sideways swipe moves to the next or previous page.
// Every Google account has its own lists in Firebase (utenti/{code}/artisti); artists are
// found on Deezer. (A module: strict mode is implied.)
import { artistIdFromLink, fansLabel, getArtist, searchArtists } from "./deezer.js";
import {
    addArtist, explainError, removeArtist, signIn, signOutUser, startFirebase, updateArtist,
    watchArtists, watchDocument,
} from "./firebase.js";

const BUILD = "__BUILD__"; // replaced by app/build_site.py with the build time
const SWIPE_MIN = 70;      // px sideways to change page
const SWIPE_EDGE = 24;     // touches starting this close to the screen edge are Android's "back" gesture
const SEARCH_DELAY_MS = 350; // wait for a pause in typing before asking Deezer

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
let stopWatching = [];
let copied = false; // "Copia codice" was just pressed
// Search on Deezer: state "idle" | "loading" | "ok" | "error"
const search = { query: "", state: "idle", results: [], error: "", timer: null, seq: 0 };
let actionError = ""; // a failed add/move/remove, shown on the page

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
    const text = actionError || (artists.state === "error" ? artists.error : "");
    return text ? `<p class="notice notice-error">${esc(text)}</p>` : "";
}

function buildLabel() {
    if (BUILD.startsWith("__")) return "versione di prova (non pubblicata)";
    const when = new Date(BUILD);
    if (Number.isNaN(when.getTime())) return `versione ${BUILD}`;
    return `versione del ${pad(when.getDate())}/${pad(when.getMonth() + 1)}/${when.getFullYear()} ${pad(when.getHours())}:${pad(when.getMinutes())}`;
}

// ------------------------------------------------------------------ list pages

function artistCard(a) {
    const detail = a.nota ? esc(a.nota) : a.fan ? esc(fansLabel(a.fan)) : "";
    return `<a class="artist-card" href="#/artista/${esc(a.id)}">
        ${photo(a.foto)}
        <span class="artist-info"><strong>${esc(a.nome)}</strong>${detail ? `<span class="small">${detail}</span>` : ""}</span>
        <span class="chevron" aria-hidden="true">›</span></a>`;
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
    return header(LISTS[lista].label, subtitle) + signInHint() + errorNotice() + body;
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
    return header("Novità", "Lo storico delle uscite che ti sono state notificate.")
        + emptyState("🔔", "Nessuna novità per ora.",
            "Le uscite nuove degli artisti in Controllare compariranno qui, dalla più recente.");
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
        ${errorNotice()}
        <h2>Lista</h2>
        <div class="segmented" role="group" aria-label="Lista">${choices}</div>
        <h2>Nota</h2>
        <textarea id="nota" data-id="${esc(a.id)}" maxlength="500" rows="3" placeholder="Ad esempio: arrivato a «Take Over»">${esc(a.nota || "")}</textarea>
        <p class="small">La nota si salva da sola quando esci dalla casella.</p>
        <h2>Discografia</h2>
        <p class="small">Tutte le uscite in ordine di data arrivano nella prossima parte. Per ora puoi vederle su Deezer.</p>
        <p class="page-actions"><button class="btn btn-danger" data-action="remove" data-id="${esc(a.id)}">Togli dalle liste</button></p>`;
}

// ------------------------------------------------------------------ account (Impostazioni)

function pageImpostazioni() {
    const install = installPrompt
        ? `<p class="card-action"><button class="btn btn-primary" data-action="install">Aggiungi alla schermata Home</button></p>`
        : "";
    return header("Impostazioni", "Il tuo account, le notifiche e l'app.")
        + `<h2>Account</h2>${accountCard()}${githubCard()}
        <h2>Notifiche</h2>
        <div class="card"><ul class="settings-list">
            <li><span>Controllo delle uscite</span><span class="value">ogni 3 ore</span></li>
            <li><span>Di notte</span><span class="value">dalle 23 alle 8 senza suono</span></li>
            <li><span>Più di 3 uscite insieme</span><span class="value">una notifica sola</span></li>
            <li><span>Featuring</span><span class="value">segnalati</span></li>
            <li><span>Copertina</span><span class="value">piccola, con tre pulsanti</span></li>
        </ul></div>
        <p class="small">Per ora queste regole sono fisse; più avanti si potranno cambiare da qui.</p>
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
    }
    return `<div class="card"><ul class="settings-list">
        <li><span>Ultimo contatto da GitHub</span><span class="value">${text}</span></li>
    </ul></div>`;
}

// ------------------------------------------------------------------ Firebase

/** Follow what belongs to the signed-in account (its artists, GitHub's status); stop when signing out. */
function followAccount() {
    stopWatching.forEach((stop) => stop());
    stopWatching = [];
    const uid = account.user?.uid;
    github = { state: uid ? "loading" : "idle", data: null, error: "" };
    artists = { state: uid ? "loading" : "idle", list: [], error: "" };
    if (!uid) return;
    stopWatching.push(watchDocument("stato/github",
        (data) => { github = { state: "ok", data, error: "" }; render(); },
        (err) => { github = { state: "error", data: null, error: explainError(err) }; render(); }));
    stopWatching.push(watchArtists(uid,
        (list) => { artists = { state: "ok", list, error: "" }; render(); },
        (err) => { artists = { state: "error", list: [], error: explainError(err) }; render(); }));
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
    } else if (typing?.id === "nota" && view.key === "artista") {
        // Writing a note: leave the page as it is until the box is left
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
    const counts = account.user ? { controllare: inList("controllare").length, recuperando: inList("recuperando").length } : {};
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
    if (action === "install" && installPrompt) {
        installPrompt.prompt();
        installPrompt.userChoice.finally(() => { installPrompt = null; render(); });
    }
});

document.addEventListener("input", (e) => {
    if (e.target.id !== "search") return;
    search.query = e.target.value;
    scheduleSearch();
});

document.addEventListener("change", (e) => {
    if (e.target.id === "nota") saveNote(e.target);
});

document.addEventListener("focusout", (e) => {
    // After leaving the note box, draw the page again with what was saved
    if (e.target.id === "nota") setTimeout(render, 0);
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
    if (e.target.closest(".nav-links, .segmented, input, select, textarea")) return; // they scroll or type by themselves
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
