// CNS (Chi Ni Sentimu) – app for the phone (and the PC).
// Pages are chosen by the hash (#/, #/recuperando, …), as in CNV's phone version: the
// menu stays on one line and a sideways swipe moves to the next or previous page.
// The lists will come from Firebase (phase 2b); for now every page is empty.
"use strict";

const BUILD = "__BUILD__"; // replaced by app/build_site.py with the build time
const SWIPE_MIN = 70;      // px sideways to change page
const SWIPE_EDGE = 24;     // touches starting this close to the screen edge are Android's "back" gesture

const PAGES = [
    { path: "/", key: "controllare", label: "Controllare", render: pageControllare },
    { path: "/recuperando", key: "recuperando", label: "Recuperando", render: pageRecuperando },
    { path: "/novita", key: "novita", label: "Novità", render: pageNovita },
    { path: "/impostazioni", key: "impostazioni", label: "Impostazioni", render: pageImpostazioni },
];

let swipeDirection = ""; // "next" | "prev": slide-in of the page drawn after a swipe
let installPrompt = null; // Chrome's "add to home screen", when it offers it

// ------------------------------------------------------------------ helpers

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

function route() {
    const hash = location.hash.replace(/^#/, "") || "/";
    const [path, query] = hash.split("?");
    return { path, params: new URLSearchParams(query || "") };
}

const currentPage = () => PAGES.find((p) => p.path === route().path) || PAGES[0];

function header(title, subtitle) {
    return `<div class="page-header"><h1>${esc(title)}</h1><p class="subtitle">${esc(subtitle)}</p></div>`;
}

function emptyState(icon, text, note) {
    return `<p class="empty-state"><span class="big" aria-hidden="true">${icon}</span>${esc(text)}<span class="small">${esc(note)}</span></p>`;
}

function buildLabel() {
    if (BUILD.startsWith("__")) return "versione di prova (non pubblicata)";
    const when = new Date(BUILD);
    if (Number.isNaN(when.getTime())) return `versione ${BUILD}`;
    const pad = (n) => String(n).padStart(2, "0");
    return `versione del ${pad(when.getDate())}/${pad(when.getMonth() + 1)}/${when.getFullYear()} ${pad(when.getHours())}:${pad(when.getMinutes())}`;
}

// ------------------------------------------------------------------ pages

function pageControllare() {
    return header("Controllare", "Gli artisti di cui vuoi sapere subito le uscite nuove.")
        + emptyState("🎧", "Nessun artista da controllare per ora.",
            "Presto potrai cercarli su Deezer e aggiungerli qui: ti arriverà una notifica a ogni uscita nuova.");
}

function pageRecuperando() {
    return header("Recuperando", "Le discografie da ascoltare dall'inizio, una uscita alla volta.")
        + emptyState("📀", "Nessuna discografia da recuperare per ora.",
            "Qui vedrai per ogni artista dove sei arrivato e cosa ti manca.");
}

function pageNovita() {
    return header("Novità", "Lo storico delle uscite che ti sono state notificate.")
        + emptyState("🔔", "Nessuna novità per ora.",
            "Le uscite nuove degli artisti in Controllare compariranno qui, dalla più recente.");
}

function pageImpostazioni() {
    const install = installPrompt
        ? `<p class="card-action"><button class="btn btn-primary" data-action="install">Aggiungi alla schermata Home</button></p>`
        : "";
    return header("Impostazioni", "Come funzionano le notifiche e l'app.")
        + `<h2>Notifiche</h2>
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

// ------------------------------------------------------------------ rendering

function render() {
    const page = currentPage();
    const app = document.getElementById("app");
    app.innerHTML = page.render();
    if (swipeDirection) {
        app.classList.remove("swipe-next", "swipe-prev");
        void app.offsetWidth; // restart the animation
        app.classList.add(`swipe-${swipeDirection}`);
        swipeDirection = "";
    }
    document.title = `${page.label} – CNS`;
    renderNav(page.key);
}

function renderNav(active) {
    const nav = document.getElementById("nav-links");
    nav.innerHTML = PAGES.map((p) =>
        `<a href="#${p.path}" class="${active === p.key ? "active" : ""}"${active === p.key ? ' aria-current="page"' : ""}>${esc(p.label)}</a>`).join("");
    // The menu scrolls sideways on narrow screens: keep the current page in view
    const current = nav.querySelector("a.active");
    if (current) nav.scrollLeft = Math.max(0, current.offsetLeft - nav.offsetLeft - (nav.clientWidth - current.offsetWidth) / 2);
}

// ------------------------------------------------------------------ events

window.addEventListener("hashchange", () => { render(); window.scrollTo(0, 0); });

document.addEventListener("click", (e) => {
    const button = e.target.closest("[data-action]");
    if (!button) return;
    if (button.dataset.action === "install" && installPrompt) {
        installPrompt.prompt();
        installPrompt.userChoice.finally(() => { installPrompt = null; render(); });
    }
});

window.addEventListener("beforeinstallprompt", (e) => {
    e.preventDefault(); // shown as a button in Impostazioni instead of Chrome's banner
    installPrompt = e;
    if (currentPage().key === "impostazioni") render();
});

// ------------------------------------------------------------------ swipe between pages

let swipe = null; // the touch in progress: {x, y, horizontal}

/** The page a swipe leads to (step +1 = next, -1 = previous), or null at the ends. */
function swipeTarget(step) {
    const index = PAGES.indexOf(currentPage());
    const target = PAGES[index + step];
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
    if (e.target.closest(".nav-links, input, select, textarea")) return; // they scroll or type by themselves
    swipe = { x: t.clientX, y: t.clientY, horizontal: null };
}, { passive: true });

document.addEventListener("touchmove", (e) => {
    if (!swipe) return;
    const dx = e.touches[0].clientX - swipe.x;
    const dy = e.touches[0].clientY - swipe.y;
    // Decide once, after a few px: sideways = swipe, otherwise the page is just scrolling
    if (swipe.horizontal === null && Math.hypot(dx, dy) > 12) swipe.horizontal = Math.abs(dx) > Math.abs(dy) * 1.5;
    if (swipe.horizontal) {
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

if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("sw.js").catch(() => { /* works without, just not offline */ });
}
