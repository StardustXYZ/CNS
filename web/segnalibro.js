// The bookmark of Recuperando: which releases of an artist were listened to or skipped.
// It is saved in the artist's document as ``fatte``: { <release key>: { s: "a" | "s", t: time } }
// ("a" = ascoltato, "s" = saltato). The key is the one of the merged release in
// discografia.js (kind + title without version marks), so a new remix of a release already
// listened to does not come back in the queue. Pure functions, no network.
import { arrange } from "./discografia.js";

export const LISTENED = "a";
export const SKIPPED = "s";
// What a discography to catch up holds by default: compilations are left out
export const DEFAULT_KINDS = ["album", "ep", "single", "featuring"];

/** The queue of an artist: the releases of the chosen kinds, oldest first, split in done and to do. */
export function queueOf(groups, fatte = {}, kinds = DEFAULT_KINDS) {
    const all = arrange(groups.filter((g) => kinds.includes(g.kind)), "", true);
    const pending = all.filter((g) => !fatte[g.key]);
    const listened = all.filter((g) => fatte[g.key]?.s === LISTENED).length;
    const skipped = all.filter((g) => fatte[g.key]?.s === SKIPPED).length;
    return { all, pending, next: pending[0] || null, listened, skipped, total: all.length, finished: all.length > 0 && !pending.length };
}

/** A copy of ``fatte`` with one release marked as listened (or skipped). */
export function mark(fatte, key, state = LISTENED, now = Date.now()) {
    return { ...fatte, [key]: { s: state, t: now } };
}

/** "Arrivato qui": every release of the queue up to this one (included) counts as listened;
 * the ones already marked keep their state. */
export function markUpTo(queueAll, key, fatte, now = Date.now()) {
    const index = queueAll.findIndex((g) => g.key === key);
    if (index === -1) return fatte;
    const result = { ...fatte };
    queueAll.slice(0, index + 1).forEach((g, i) => {
        if (!result[g.key]) result[g.key] = { s: LISTENED, t: now + i }; // in order, so "undo" goes back one at a time
    });
    return result;
}

/** A copy of ``fatte`` without the most recent mark (and that mark's key, or null). */
export function undoLast(fatte) {
    let lastKey = null;
    for (const [key, value] of Object.entries(fatte || {})) {
        if (!lastKey || (value?.t || 0) >= (fatte[lastKey]?.t || 0)) lastKey = key;
    }
    if (!lastKey) return { fatte: fatte || {}, key: null };
    const { [lastKey]: _removed, ...rest } = fatte;
    return { fatte: rest, key: lastKey };
}

/** Undo the mark of one release ("non l'ho ancora ascoltato"). */
export function unmark(fatte, key) {
    const { [key]: _removed, ...rest } = fatte || {};
    return rest;
}

/** "12 di 51" with the percentage for the progress bar. */
export function progress(queue) {
    const done = queue.listened + queue.skipped;
    return { done, total: queue.total, percent: queue.total ? Math.round((done / queue.total) * 100) : 0 };
}
