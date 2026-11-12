// Service worker: CNS opens even without connection (from CNV's sw.js).
// __BUILD__ is replaced at every build, so phones get the new app after an update.
const CACHE = "cns-__BUILD__";
const SHELL = ["./", "index.html", "app.js", "firebase.js", "deezer.js", "style.css", "manifest.webmanifest",
    "icons/icon-192.png", "icons/icon-512.png", "icons/icon-maskable-512.png"];
// Photos and covers from Deezer get their own cache, kept across app updates
const COVERS = "cns-covers";
const isDeezerImage = (url) => url.hostname.endsWith(".dzcdn.net");
// Firebase's code from Google's servers: the address holds the version, so a saved copy never changes
const LIBS = "cns-libs";
const LIBS_PREFIX = "https://www.gstatic.com/firebasejs/";

self.addEventListener("install", (event) => {
    // Straight from the server: a copy in the browser's HTTP cache could be the previous version
    const fresh = SHELL.map((url) => new Request(url, { cache: "reload" }));
    event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(fresh)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
    event.waitUntil(
        caches.keys()
            .then((keys) => Promise.all(keys.filter((k) => ![CACHE, COVERS, LIBS].includes(k)).map((k) => caches.delete(k))))
            .then(() => self.clients.claim())
    );
});

self.addEventListener("fetch", (event) => {
    if (event.request.method !== "GET") return;
    const url = new URL(event.request.url);
    if (url.href.startsWith(LIBS_PREFIX)) {
        // Firebase's code: the saved copy first, so the app works offline after the first visit
        event.respondWith(caches.open(LIBS).then((cache) =>
            cache.match(event.request).then((hit) => hit || fetch(event.request).then((resp) => {
                if (resp.ok) cache.put(event.request, resp.clone());
                return resp;
            }))));
        return;
    }
    if (isDeezerImage(url)) {
        // Artist photos: the saved copy first, so the lists look the same offline
        event.respondWith(caches.open(COVERS).then((cache) =>
            cache.match(event.request).then((hit) => hit || fetch(event.request).then((resp) => {
                if (resp.ok || resp.type === "opaque") cache.put(event.request, resp.clone());
                return resp;
            }))));
        return;
    }
    if (url.origin === self.location.origin) {
        // The app's own files: the saved copy first (instant and offline), the network otherwise
        event.respondWith(caches.match(event.request, { ignoreSearch: true }).then((hit) => hit || fetch(event.request)));
    }
});
