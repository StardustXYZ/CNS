// Backup and restore of a person's data (web/copia.js).
import assert from "node:assert/strict";
import { test } from "node:test";
import { FORMAT, backupFileName, buildBackup, parseBackup } from "../copia.js";

const when = new Date("2026-11-13T20:00:00Z");
const timestamp = (iso) => ({ toDate: () => new Date(iso) }); // like Firestore's Timestamp

const AVA = { id: "12948083", nome: "Ava Max", lista: "controllare", nota: "", foto: "https://cdn/ava.jpg", fan: 1235611,
    tipi_avviso: ["album", "single"], aggiunto: timestamp("2026-11-12T19:00:00Z") };
const LOL = { id: "7402526", nome: "League of Legends", lista: "recuperando", nota: "",
    fatte: { "single|take over": { s: "a", t: 1763000000000 } }, tipi_recupero: ["album", "single"], auto_sposta: true,
    canzoni: { "album|arcane league of legends": { "enemy": 1763000000001, "playground": 1763000000002 } } };

test("la copia contiene artisti, argomento ntfy e storico, con le date in testo", () => {
    const backup = buildBackup({ artists: [AVA, LOL], settings: { ntfy: "cns-abc", email: "x@example.com" },
        novita: [{ id: "1", titolo: "Christmas Wonderland", notificata: timestamp("2026-11-13T18:00:00Z") }], email: "x@example.com", now: when });
    assert.equal(backup.formato, FORMAT);
    assert.equal(backup.salvata, "2026-11-13T20:00:00.000Z");
    assert.equal(backup.impostazioni.ntfy, "cns-abc");
    assert.equal(backup.artisti.length, 2);
    assert.equal(backup.artisti[0].aggiunto, "2026-11-12T19:00:00.000Z");
    assert.deepEqual(backup.artisti[1].fatte, LOL.fatte);
    assert.equal(backup.novita[0].notificata, "2026-11-13T18:00:00.000Z");
    assert.doesNotThrow(() => JSON.stringify(backup));
});

test("nome del file con la data", () => {
    assert.equal(backupFileName(new Date(2026, 10, 3)), "cns-copia-2026-11-03.json");
});

test("il ripristino riprende artisti, segnalibro e argomento", () => {
    const text = JSON.stringify(buildBackup({ artists: [AVA, LOL], settings: { ntfy: "cns-abc" }, now: when }));
    const restored = parseBackup(text);
    assert.equal(restored.artists.length, 2);
    assert.equal(restored.ntfy, "cns-abc");
    assert.equal(restored.skipped, 0);
    const lol = restored.artists.find((a) => a.id === "7402526");
    assert.deepEqual(lol.fatte, LOL.fatte);
    assert.deepEqual(lol.canzoni, LOL.canzoni); // the songs ticked in the Android app come back too
    assert.equal(lol.auto_sposta, true);
    assert.equal(restored.artists[0].aggiunto, undefined); // not restored: Firebase sets its own
});

test("gli artisti non validi vengono saltati, gli altri restano", () => {
    const text = JSON.stringify({ formato: FORMAT, versione: 1, artisti: [
        AVA, { id: "abc", nome: "Codice sbagliato", lista: "controllare" }, { id: "1", nome: "", lista: "controllare" },
        { id: "2", nome: "Lista sbagliata", lista: "boh" }, { id: "3", nome: "Nota lunga", lista: "archivio", nota: "x".repeat(600) },
    ] });
    const restored = parseBackup(text);
    assert.deepEqual(restored.artists.map((a) => a.id), ["12948083", "3"]);
    assert.equal(restored.skipped, 3);
    assert.equal(restored.artists[1].nota.length, 500);
    assert.equal(restored.ntfy, null);
});

test("file sbagliati: messaggi chiari", () => {
    assert.throws(() => parseBackup("non json"), /non è JSON/);
    assert.throws(() => parseBackup(JSON.stringify({ votes: {} })), /non è una copia di CNS/);
    assert.throws(() => parseBackup(JSON.stringify({ formato: FORMAT, versione: 99, artisti: [] })), /versione più nuova/);
    assert.equal(parseBackup(JSON.stringify({ formato: FORMAT, versione: 1, artisti: [], impostazioni: { ntfy: "con spazi" } })).ntfy, null);
});

// The Android app writes the same file (mobile/lib/data/copia.dart): its copy is restored here
import { readFileSync as readFixture } from "node:fs";

test("una copia fatta dall'app Android si ripristina nell'app web", () => {
    const text = readFixture(new URL("../../tests/fixtures/copia_app.json", import.meta.url), "utf8");
    const restored = parseBackup(text);
    assert.deepEqual(restored.artists.map((a) => a.id), ["4050205", "7402526"]);
    assert.equal(restored.ntfy, "cns-prova-123");
    assert.equal(restored.skipped, 0);
    const lol = restored.artists[1];
    assert.deepEqual(lol.fatte, { "single|warriors": { s: "a", t: 1763000000000 } });
    assert.deepEqual(lol.canzoni, { "album|arcane league of legends": { enemy: 1763000000002, playground: 1763000000003 } });
    assert.equal(restored.artists[0].aggiunto, undefined);
});

test("al ripristino i link e le foto che non sono indirizzi web vengono tolti", () => {
    const evil = { ...AVA, foto: "javascript:alert(1)", link: "data:text/html,<script>alert(1)</script>" };
    const fine = { ...LOL, foto: "https://cdn/lol.jpg", link: "https://www.deezer.com/artist/7402526" };
    const text = JSON.stringify({ formato: FORMAT, versione: 1, artisti: [evil, fine] });
    const { artists, skipped } = parseBackup(text);
    assert.equal(skipped, 0);
    assert.equal(artists.length, 2);  // the artist stays: only the bad addresses go
    assert.ok(!("foto" in artists[0]) && !("link" in artists[0]));
    assert.equal(artists[0].nome, "Ava Max");
    assert.equal(artists[1].foto, "https://cdn/lol.jpg");
    assert.equal(artists[1].link, "https://www.deezer.com/artist/7402526");
});
