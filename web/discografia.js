// An artist's discography from Deezer, with the duplicates merged.
// Deezer lists every version as a separate release: remixes, deluxe and explicit/clean
// editions, acoustic and live versions. Here they become "versions" of one release, shown
// under the original. Pure functions (tested in web/test/discografia.test.mjs), no network.
import { normalize } from "./deezer.js";

export const KINDS = {
    album: { label: "Album", plural: "Album" },
    ep: { label: "EP", plural: "EP" },
    single: { label: "Singolo", plural: "Singoli" },
    featuring: { label: "Featuring", plural: "Featuring" },
    compile: { label: "Raccolta", plural: "Raccolte" },
};

// Words that mark a version of the same release, inside "( )", "[ ]" or after " - "
const VERSION_WORDS = /\b(deluxe|edition|version|explicit|clean|remaster(ed)?|bonus|expanded|extended|anniversary|remix(es)?|mix|sped up|slowed|reverb|acoustic|instrumental|without dialogue|demo|live|feat\.?|ft\.?|featuring|with)\b/i;
// "(feat. X)", "ft. X", "featuring X", "(with X)": the names after it are the guests
const FEAT = /(?:\b(?:feat|ft)\b\.?|\bfeaturing\b|[(\[]\s*with\b)\s*([^)\]]+)/gi;

/** One release from Deezer's answer (artist/{id}/albums). */
export function releaseFromApi(hit) {
    const date = /^\d{4}-\d{2}-\d{2}$/.test(hit.release_date || "") && hit.release_date !== "0000-00-00" ? hit.release_date : "";
    return {
        id: String(hit.id),
        title: hit.title || "",
        type: String(hit.record_type || hit.type || "album").toLowerCase(),
        date,
        cover: hit.cover_medium || hit.cover_big || hit.cover || "",
        link: hit.link || `https://www.deezer.com/album/${hit.id}`,
        explicit: Boolean(hit.explicit_lyrics),
    };
}

/** The title without the version marks: "Sweet but Psycho (Leon Lour Remix)" -> "Sweet but Psycho". */
export function baseTitle(title) {
    let t = String(title || "").trim();
    for (;;) {
        const match = t.match(/\s*(?:\(([^()]*)\)|\[([^\[\]]*)\]|\s-\s([^-]+))\s*$/);
        if (!match || !VERSION_WORDS.test(match[1] ?? match[2] ?? match[3])) return t;
        const shorter = t.slice(0, match.index).trim();
        if (!shorter) return t;
        t = shorter;
    }
}

/** True when the artist is a guest named in the title, e.g. "BURN (feat. Ava Max)". */
export function isFeaturing(title, artistName) {
    const wanted = normalize(artistName);
    if (!wanted) return false;
    for (const [, guests] of String(title || "").matchAll(FEAT)) {
        if (` ${normalize(guests)} `.includes(` ${wanted} `)) return true;
    }
    return false;
}

/** The kind shown in the app: album, ep, single, featuring or compile. */
export function kindOf(release, artistName) {
    if (isFeaturing(release.title, artistName)) return "featuring";
    return KINDS[release.type] ? release.type : "album";
}

/** The key shared by all the versions of a release (the same as group_key() in
 * app/services/discografia.py, used by the check on GitHub). */
export function groupKey(release, artistName) {
    const kind = kindOf(release, artistName);
    const family = kind === "ep" ? "album" : kind; // an EP and its deluxe album are the same release
    return `${family}|${normalize(baseTitle(release.title))}`;
}

/** Merge the versions: same title without the version marks, same kind (an album and the
 * single with its name stay apart). The original is the one without marks, else the oldest. */
export function groupReleases(releases, artistName) {
    const groups = new Map();
    for (const r of releases) {
        const kind = kindOf(r, artistName);
        const key = groupKey(r, artistName);
        if (!groups.has(key)) groups.set(key, { key, kind, releases: [] });
        groups.get(key).releases.push(r);
    }
    return [...groups.values()].map((g) => {
        const byDate = [...g.releases].sort((a, b) => (a.date || "9999").localeCompare(b.date || "9999") || a.title.localeCompare(b.title));
        const plain = byDate.find((r) => r.title.trim() === baseTitle(r.title));
        const main = plain || byDate[0];
        return { key: g.key, kind: kindOf(main, artistName), main, date: main.date, versions: byDate.filter((r) => r !== main) };
    });
}

/** How many releases of each kind: {album: 3, single: 40, …}. */
export function countKinds(groups) {
    const counts = {};
    for (const g of groups) counts[g.kind] = (counts[g.kind] || 0) + 1;
    return counts;
}

/** The groups of one kind ("" = all), by date: oldest first or newest first; undated last. */
export function arrange(groups, kind = "", oldestFirst = false) {
    const chosen = kind ? groups.filter((g) => g.kind === kind) : groups;
    return [...chosen].sort((a, b) => {
        if (!a.date !== !b.date) return a.date ? -1 : 1;
        const order = (a.date || "").localeCompare(b.date || "") || a.main.title.localeCompare(b.main.title);
        return oldestFirst ? order : -order;
    });
}

/** "06/11/2026" from "2026-11-06"; "data sconosciuta" without a date. */
export function dateLabel(iso) {
    if (!iso) return "data sconosciuta";
    const [y, m, d] = iso.split("-");
    return `${d}/${m}/${y}`;
}

/** Spotify's search page for the release; on Android it opens the Spotify app (no exact link without its API). */
export function spotifySearchUrl(artist, title) {
    return `https://open.spotify.com/search/${encodeURIComponent(`${artist} ${title}`.trim())}`;
}
