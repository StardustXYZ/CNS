// Firestore rules, tested on the local emulator (project "demo-cns": never the real data).
// Run with: npm test (inside the firebase folder; needs Java for the emulator).
import { readFileSync } from "node:fs";
import { after, before, beforeEach, test } from "node:test";
import { assertFails, assertSucceeds, initializeTestEnvironment } from "@firebase/rules-unit-testing";
import { collection, deleteDoc, doc, getDoc, getDocs, setDoc, updateDoc } from "firebase/firestore";

let env;

before(async () => {
    env = await initializeTestEnvironment({
        projectId: "demo-cns",
        firestore: { rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8") },
    });
});
after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const as = (uid) => env.authenticatedContext(uid).firestore();
const anonymous = () => env.unauthenticatedContext().firestore();
const AVA = { nome: "Ava Max", lista: "controllare", nota: "", foto: "https://cdn/ava.jpg", fan: 1235611 };

/** A document written by GitHub (the service account skips the rules). */
async function seed(path, data) {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), path), data));
}

test("ognuno legge e scrive i suoi artisti", async () => {
    const db = as("vincenzo");
    await assertSucceeds(setDoc(doc(db, "utenti/vincenzo/artisti/12948083"), AVA));
    await assertSucceeds(getDoc(doc(db, "utenti/vincenzo/artisti/12948083")));
    await assertSucceeds(getDocs(collection(db, "utenti/vincenzo/artisti")));
    await assertSucceeds(updateDoc(doc(db, "utenti/vincenzo/artisti/12948083"), { lista: "recuperando", nota: "dal primo album" }));
    await assertSucceeds(deleteDoc(doc(db, "utenti/vincenzo/artisti/12948083")));
});

test("ognuno legge e scrive le sue impostazioni", async () => {
    await assertSucceeds(setDoc(doc(as("vincenzo"), "utenti/vincenzo"), { creato: new Date() }));
    await assertSucceeds(getDoc(doc(as("vincenzo"), "utenti/vincenzo")));
});

test("nessuno vede o cambia le liste di un altro", async () => {
    await seed("utenti/vincenzo/artisti/12948083", AVA);
    const friend = as("amico");
    await assertFails(getDoc(doc(friend, "utenti/vincenzo/artisti/12948083")));
    await assertFails(getDocs(collection(friend, "utenti/vincenzo/artisti")));
    await assertFails(setDoc(doc(friend, "utenti/vincenzo/artisti/1"), AVA));
    await assertFails(deleteDoc(doc(friend, "utenti/vincenzo/artisti/12948083")));
    await assertFails(getDoc(doc(friend, "utenti/vincenzo")));
});

test("chi non ha fatto l'accesso non vede niente", async () => {
    await seed("utenti/vincenzo/artisti/12948083", AVA);
    await seed("stato/github", { ultimo_contatto: new Date() });
    await assertFails(getDoc(doc(anonymous(), "utenti/vincenzo/artisti/12948083")));
    await assertFails(getDoc(doc(anonymous(), "stato/github")));
});

test("lo stato di GitHub si legge con l'accesso ma non si scrive dall'app", async () => {
    await seed("stato/github", { ultimo_contatto: new Date() });
    await assertSucceeds(getDoc(doc(as("vincenzo"), "stato/github")));
    await assertFails(setDoc(doc(as("vincenzo"), "stato/github"), { ultimo_contatto: new Date() }));
});

test("un artista deve avere nome, lista valida e codice Deezer numerico", async () => {
    const db = as("vincenzo");
    await assertFails(setDoc(doc(db, "utenti/vincenzo/artisti/12948083"), { ...AVA, lista: "boh" }));
    await assertFails(setDoc(doc(db, "utenti/vincenzo/artisti/12948083"), { ...AVA, nome: "" }));
    await assertFails(setDoc(doc(db, "utenti/vincenzo/artisti/12948083"), { lista: "controllare" }));
    await assertFails(setDoc(doc(db, "utenti/vincenzo/artisti/ava-max"), AVA));
    await assertFails(setDoc(doc(db, "utenti/vincenzo/artisti/12948083"), { ...AVA, nota: "x".repeat(501) }));
    await assertSucceeds(setDoc(doc(db, "utenti/vincenzo/artisti/12948083"), { nome: "Ava Max", lista: "archivio" }));
});

test("le raccolte non previste sono chiuse a tutti", async () => {
    await assertFails(setDoc(doc(as("vincenzo"), "utenti/vincenzo/altro/1"), { x: 1 }));
    await assertFails(setDoc(doc(as("vincenzo"), "qualcosa/1"), { x: 1 }));
});
