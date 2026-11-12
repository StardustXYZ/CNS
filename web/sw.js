// Service worker: CNS opens even without connection (from CNV's sw.js).
// __BUILD__ is replaced at every build, so phones get the new app after an update.
const CACHE = "cns-__BUILD__";
const SHELL = ["./", "index.html", "app.js", "style.css", "manifest.webmanifest",
    "icons/icon-192.png", "icons/icon-512.png", "icons/icon-maskable-512.png"];
// Covers from Deezer get their own cache, kept across app updates (used from phase 3)
const COVERS = "cns-covers";

self.addEventListener("install", (event) => {
    // Straight from the server: a copy in the browser's HTTP cache could be the previous version
    const fresh = SHELL.map((url) => new Request(url, { cache: "reload" }));
    event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(fresh)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
    event.waitUntil(
        caches.keys()
            .then((keys) => Promise.all(keys.filter((k) => ![CACHE, COVERS].includes(k)).map((k) => caches.delete(k))))
            .then(() => self.clients.claim())
    );
});

self.addEventListener("fetch", (event) => {
    if (event.request.method !== "GET") return;
    const url = new URL(event.request.url);
    if (url.origin === self.location.origin) {
        // The app's own files: the saved copy first (instant and offline), the network otherwise
        event.respondWith(caches.match(event.request, { ignoreSearch: true }).then((hit) => hit || fetch(event.request)));
    }
});
