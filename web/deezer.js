// Deezer from the phone: artist search and artist details.
// Deezer's API does not let a web page read it directly (no CORS), but it answers in
// "JSONP": the answer comes back as a script that calls one of our functions.

const API = "https://api.deezer.com";
const TIMEOUT_MS = 10000;
let counter = 0;

/** Lowercase, no accents, no punctuation: "Beyoncé" and "beyonce" match (as in app/services/titles.py). */
export function normalize(text) {
    return String(text || "").toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "")
        .replace(/[^\p{L}\p{N}\s]/gu, " ").replace(/\s+/g, " ").trim();
}

/** The artist code in a Deezer link ("https://www.deezer.com/it/artist/12948083?..."), or null. */
export function artistIdFromLink(text) {
    const match = String(text || "").match(/deezer\.com\/(?:[a-z]{2}(?:-[a-z]{2})?\/)?artist\/(\d{1,20})/i);
    return match ? match[1] : null;
}

/** Results in the best order: the exact name with the most fans first (Deezer does not
 * always put the right artist first: "Amy Lee" the singer is fifth), then Deezer's order. */
export function rankArtists(query, artists) {
    const wanted = normalize(query);
    const exact = artists.filter((a) => normalize(a.name) === wanted).sort((a, b) => b.fans - a.fans);
    return [...exact, ...artists.filter((a) => !exact.includes(a))];
}

/** "1,2 mln di fan", "136.074 fan", "1 fan". */
export function fansLabel(fans) {
    if (fans >= 1e6) return `${(fans / 1e6).toLocaleString("it-IT", { maximumFractionDigits: 1 })} mln di fan`;
    return `${fans.toLocaleString("it-IT")} fan`;
}

export function artistFromApi(hit) {
    return {
        id: String(hit.id),
        name: hit.name || "",
        picture: hit.picture_big || hit.picture_medium || hit.picture || "",
        fans: Number(hit.nb_fan || 0),
        albums: Number(hit.nb_album || 0),
        link: hit.link || `https://www.deezer.com/artist/${hit.id}`,
    };
}

/** Call the API through a script tag; rejects on errors and after a timeout. */
export function jsonp(path, params = {}) {
    return new Promise((resolve, reject) => {
        const name = `cnsDeezer${Date.now()}${counter++}`;
        const query = new URLSearchParams({ ...params, output: "jsonp", callback: name });
        const script = document.createElement("script");
        const done = () => { clearTimeout(timer); delete window[name]; script.remove(); };
        const timer = setTimeout(() => { done(); reject(new Error("Deezer non risponde")); }, TIMEOUT_MS);
        window[name] = (data) => {
            done();
            if (data && data.error) reject(new Error(data.error.message || "errore di Deezer"));
            else resolve(data);
        };
        script.onerror = () => { done(); reject(new Error("Deezer non raggiungibile")); };
        script.src = `${API}${path}?${query}`;
        document.head.appendChild(script);
    });
}

export async function searchArtists(query) {
    const data = await jsonp("/search/artist", { q: query, limit: 15 });
    return rankArtists(query, (data.data || []).map(artistFromApi));
}

export async function getArtist(id) {
    return artistFromApi(await jsonp(`/artist/${encodeURIComponent(id)}`));
}

const PAGE_SIZE = 100;
const MAX_PAGES = 50; // a safety stop: 5000 releases

/** Every item of an artist's discography as Deezer gives it (all pages; raw objects). */
export async function getDiscography(id) {
    const items = [];
    for (let page = 0; page < MAX_PAGES; page++) {
        const data = await jsonp(`/artist/${encodeURIComponent(id)}/albums`, { limit: PAGE_SIZE, index: page * PAGE_SIZE });
        items.push(...(data.data || []));
        if (!data.next || !(data.data || []).length) break;
    }
    return items;
}
