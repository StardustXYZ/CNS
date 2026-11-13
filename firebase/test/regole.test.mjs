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
// Admitted: the administrator "vincenzo" and the e-mail of "amico"; "estraneo" is not
const ALLOW_LIST = { admin: "vincenzo", email: ["amico@example.com"] };
beforeEach(async () => {
    await env.clearFirestore();
    await seed("config/ammessi", ALLOW_LIST);
});

/** A signed-in Google account: its e-mail is "<uid>@example.com" (verified, as with Google). */
const as = (uid, email = `${uid}@example.com`, verified = true) =>
    env.authenticatedContext(uid, { email, email_verified: verified }).firestore();
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

test("l'argomento ntfy si salva solo se è un nome valido", async () => {
    const db = as("vincenzo");
    await assertSucceeds(setDoc(doc(db, "utenti/vincenzo"), { ntfy: "cns-AbC_123-xyz" }));
    await assertSucceeds(setDoc(doc(db, "utenti/vincenzo"), { ntfy: "" }));
    await assertFails(setDoc(doc(db, "utenti/vincenzo"), { ntfy: "https://ntfy.sh/cns" }));
    await assertFails(setDoc(doc(db, "utenti/vincenzo"), { ntfy: "con spazi" }));
    await assertFails(setDoc(doc(db, "utenti/vincenzo"), { ntfy: "x".repeat(65) }));
    await assertFails(setDoc(doc(as("amico"), "utenti/vincenzo"), { ntfy: "rubato" }));
});

test("le Novità le scrive solo GitHub: si leggono e si cancellano, non si scrivono", async () => {
    await seed("utenti/vincenzo/novita/1139685681", { titolo: "Christmas Wonderland" });
    const db = as("vincenzo");
    await assertSucceeds(getDoc(doc(db, "utenti/vincenzo/novita/1139685681")));
    await assertSucceeds(getDocs(collection(db, "utenti/vincenzo/novita")));
    await assertFails(setDoc(doc(db, "utenti/vincenzo/novita/1"), { titolo: "Falsa" }));
    await assertFails(getDocs(collection(as("amico"), "utenti/vincenzo/novita")));
    await assertSucceeds(deleteDoc(doc(db, "utenti/vincenzo/novita/1139685681")));
});

test("le uscite già viste (visti) restano chiuse all'app", async () => {
    await seed("visti/12948083", { ids: ["1"] });
    await assertFails(getDoc(doc(as("vincenzo"), "visti/12948083")));
    await assertFails(setDoc(doc(as("vincenzo"), "visti/12948083"), { ids: [] }));
});

test("le uscite in arrivo le scrive solo GitHub: si leggono, non si scrivono, gli altri non le vedono", async () => {
    await seed("utenti/vincenzo/anteprime/950", { titolo: "Nuovo Album", data: "2026-12-04" });
    const db = as("vincenzo");
    await assertSucceeds(getDocs(collection(db, "utenti/vincenzo/anteprime")));
    await assertFails(setDoc(doc(db, "utenti/vincenzo/anteprime/951"), { titolo: "Falsa" }));
    await assertFails(getDocs(collection(as("amico"), "utenti/vincenzo/anteprime")));
});

// ---- Lista degli ammessi (2d) ----

test("chi non è tra gli ammessi non entra nemmeno nella sua cartella", async () => {
    const db = as("estraneo");
    await assertFails(setDoc(doc(db, "utenti/estraneo/artisti/12948083"), AVA));
    await assertFails(getDocs(collection(db, "utenti/estraneo/artisti")));
    await assertFails(setDoc(doc(db, "utenti/estraneo"), { ntfy: "argomento" }));
    await seed("stato/github", { ultimo_contatto: new Date() });
    await assertFails(getDoc(doc(db, "stato/github")));
});

test("un'email ammessa entra solo se verificata, e senza badare alle maiuscole", async () => {
    await assertSucceeds(setDoc(doc(as("amico", "Amico@Example.com"), "utenti/amico/artisti/12948083"), AVA));
    await assertFails(setDoc(doc(as("amico", "amico@example.com", false), "utenti/amico/artisti/1"), AVA));
});

test("solo l'amministratore legge e cambia la lista, ma non può cambiare chi è l'amministratore", async () => {
    await assertSucceeds(getDoc(doc(as("vincenzo"), "config/ammessi")));
    await assertSucceeds(updateDoc(doc(as("vincenzo"), "config/ammessi"), { email: ["amico@example.com", "mamma@example.com"] }));
    await assertFails(updateDoc(doc(as("vincenzo"), "config/ammessi"), { admin: "qualcun-altro" }));
    await assertFails(updateDoc(doc(as("vincenzo"), "config/ammessi"), { email: ["x"], altro: true }));
    await assertFails(getDoc(doc(as("amico"), "config/ammessi")));
    await assertFails(updateDoc(doc(as("amico"), "config/ammessi"), { email: ["amico@example.com", "intruso@example.com"] }));
    await assertFails(deleteDoc(doc(as("vincenzo"), "config/ammessi")));
});

test("senza la lista degli ammessi non entra nessuno", async () => {
    await env.withSecurityRulesDisabled((ctx) => deleteDoc(doc(ctx.firestore(), "config/ammessi")));
    await assertFails(getDocs(collection(as("vincenzo"), "utenti/vincenzo/artisti")));
    await assertFails(setDoc(doc(as("vincenzo"), "config/ammessi"), ALLOW_LIST)); // it is created only in the console
});
