// Bookmark of Recuperando: queue, listened/skipped, "arrivato qui", undo, end of the discography.
import assert from "node:assert/strict";
import { test } from "node:test";
import { groupReleases, releaseFromApi } from "../discografia.js";
import { LISTENED, SKIPPED, mark, markUpTo, progress, queueOf, undoLast, unmark } from "../segnalibro.js";

let next = 1;
const rel = (title, date, type = "single") => releaseFromApi({ id: next++, title, release_date: date, record_type: type });

// League of Legends, a few real titles (Deezer, November 2026)
const groups = groupReleases([
    rel("Warriors", "2014-09-19"),
    rel("Legends Never Die", "2017-09-21"),
    rel("Legends Never Die (Remix)", "2018-01-10"),
    rel("RISE", "2018-09-24"),
    rel("Take Over", "2020-09-23"),
    rel("Arcane League of Legends (Soundtrack from the Animated Series)", "2021-11-20", "album"),
    rel("Worlds Collection", "2022-01-01", "compile"),
    rel("GODS", "2023-10-03"),
], "League of Legends");
const keyOf = (title) => groups.find((g) => g.main.title === title).key;

test("la coda va dalla più vecchia e lascia fuori le raccolte", () => {
    const q = queueOf(groups);
    assert.deepEqual(q.all.map((g) => g.main.title), ["Warriors", "Legends Never Die", "RISE", "Take Over", "Arcane League of Legends (Soundtrack from the Animated Series)", "GODS"]);
    assert.equal(q.next.main.title, "Warriors");
    assert.equal(q.total, 6); // the remix is a version of Legends Never Die
    assert.equal(q.finished, false);
});

test("Ascoltato e Salta fanno avanzare il segnalibro", () => {
    let fatte = mark({}, keyOf("Warriors"), LISTENED, 1);
    fatte = mark(fatte, keyOf("Legends Never Die"), SKIPPED, 2);
    const q = queueOf(groups, fatte);
    assert.equal(q.next.main.title, "RISE");
    assert.equal(q.listened, 1);
    assert.equal(q.skipped, 1);
    assert.deepEqual(progress(q), { done: 2, total: 6, percent: 33 });
});

test("«Arrivato qui» segna tutto fino a quella uscita, senza cambiare le saltate", () => {
    const start = mark({}, keyOf("Legends Never Die"), SKIPPED, 1);
    const fatte = markUpTo(queueOf(groups).all, keyOf("Take Over"), start, 100);
    const q = queueOf(groups, fatte);
    assert.equal(q.next.main.title, "Arcane League of Legends (Soundtrack from the Animated Series)");
    assert.equal(fatte[keyOf("Legends Never Die")].s, SKIPPED);
    assert.equal(fatte[keyOf("Take Over")].s, LISTENED);
    assert.equal(q.listened, 3);
});

test("«Annulla» toglie l'ultimo segno, uno alla volta", () => {
    let fatte = markUpTo(queueOf(groups).all, keyOf("RISE"), {}, 100); // Warriors, Legends, RISE
    let undone = undoLast(fatte);
    assert.equal(undone.key, keyOf("RISE"));
    undone = undoLast(undone.fatte);
    assert.equal(undone.key, keyOf("Legends Never Die"));
    assert.equal(queueOf(groups, undone.fatte).next.main.title, "Legends Never Die");
    assert.deepEqual(undoLast({}), { fatte: {}, key: null });
    fatte = unmark(fatte, keyOf("Warriors"));
    assert.equal(queueOf(groups, fatte).next.main.title, "Warriors");
});

test("fine della discografia e uscite nuove in fondo alla coda", () => {
    const fatte = markUpTo(queueOf(groups).all, keyOf("GODS"), {}, 1);
    assert.equal(queueOf(groups, fatte).finished, true);
    // A new release comes out: the queue is open again, with only that one
    const withNew = [...groups, ...groupReleases([rel("Ignite (2026)", "2026-11-13")], "League of Legends")];
    const q = queueOf(withNew, fatte);
    assert.equal(q.finished, false);
    assert.equal(q.next.main.title, "Ignite (2026)");
    assert.equal(q.pending.length, 1);
});

test("i tipi scelti decidono cosa entra nella coda", () => {
    const q = queueOf(groups, {}, ["album"]);
    assert.deepEqual(q.all.map((g) => g.main.title), ["Arcane League of Legends (Soundtrack from the Animated Series)"]);
    assert.equal(queueOf([], {}).finished, false); // nothing to catch up is not "finished"
});
