// Backup of one person's CNS data as a JSON file (as in CNV's "copia di sicurezza").
// The file holds the artists (lists, notes, bookmark, alert kinds), the ntfy topic, the
// Novità and the announced releases. Restoring brings back the artists and the topic; the
// Novità and "In arrivo" are written only by GitHub, so they stay in the file as a record.
// Pure functions (tested in web/test/copia.test.mjs), no network.

export const FORMAT = "cns-copia";
export const VERSION = 1;
const LISTS = ["controllare", "recuperando", "archivio"];
const ARTIST_FIELDS = ["nome", "foto", "link", "fan", "lista", "nota", "fatte", "tipi_recupero", "tipi_avviso", "auto_sposta", "fine_tenuta"];

/** Firestore's dates (Timestamp) as ISO text, everything else as it is. */
function plain(value) {
    if (value && typeof value.toDate === "function") return value.toDate().toISOString();
    if (Array.isArray(value)) return value.map(plain);
    if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, plain(v)]));
    return value;
}

/** The backup object, ready for JSON.stringify. */
export function buildBackup({ artists = [], settings = {}, novita = [], anteprime = [], email = "", now = new Date() }) {
    return {
        formato: FORMAT,
        versione: VERSION,
        salvata: now.toISOString(),
        account: email,
        impostazioni: { ntfy: settings.ntfy || "" },
        artisti: artists.map((a) => plain({ id: a.id, ...a })),
        novita: novita.map((n) => plain(n)),
        in_arrivo: anteprime.map((n) => plain(n)),
    };
}

/** "cns-copia-2026-11-13.json". */
export function backupFileName(now = new Date()) {
    const pad = (n) => String(n).padStart(2, "0");
    return `cns-copia-${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}.json`;
}

/** Read a backup file: {artists: [{id, ...fields}], ntfy, count} or an error in Italian. */
export function parseBackup(text) {
    let data;
    try {
        data = JSON.parse(text);
    } catch {
        throw new Error("il file non è una copia di CNS (non è JSON)");
    }
    if (!data || data.formato !== FORMAT || !Array.isArray(data.artisti)) {
        throw new Error("il file non è una copia di CNS");
    }
    if (Number(data.versione) > VERSION) {
        throw new Error("la copia è di una versione più nuova di CNS: aggiorna l'app e riprova");
    }
    const artists = [];
    for (const raw of data.artisti) {
        const id = String(raw?.id ?? "");
        if (!/^[0-9]{1,20}$/.test(id) || typeof raw.nome !== "string" || !raw.nome.trim() || !LISTS.includes(raw.lista)) continue;
        const fields = Object.fromEntries(ARTIST_FIELDS.filter((k) => raw[k] !== undefined).map((k) => [k, raw[k]]));
        fields.nome = fields.nome.slice(0, 200);
        if (typeof fields.nota !== "string") fields.nota = "";
        fields.nota = fields.nota.slice(0, 500);
        artists.push({ id, ...fields });
    }
    const ntfy = typeof data.impostazioni?.ntfy === "string" && /^[A-Za-z0-9_-]{0,64}$/.test(data.impostazioni.ntfy)
        ? data.impostazioni.ntfy : null;
    return { artists, ntfy, skipped: data.artisti.length - artists.length, saved: data.salvata || "" };
}
