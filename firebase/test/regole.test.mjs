// Firestore rules, tested on the local emulator (project "demo-cns": never the real data).
// Run with: npm test (inside the firebase folder; needs Java for the emulator).
import { readFileSync } from "node:fs";
import { after, before, beforeEach, test } from "node:test";
import { assertFails, assertSucceeds, initializeTestEnvironment } from "@firebase/rules-unit-testing";
import { deleteDoc, doc, getDoc, setDoc } from "firebase/firestore";

const OWNER = "proprietario-di-prova";
const template = readFileSync(new URL("../firestore.rules", import.meta.url), "utf8");
let env;

before(async () => {
    env = await initializeTestEnvironment({
        projectId: "demo-cns",
        firestore: { rules: template.replaceAll("__OWNER_UID__", OWNER) },
    });
});
after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const owner = () => env.authenticatedContext(OWNER).firestore();
const stranger = () => env.authenticatedContext("un-altro-account").firestore();
const anonymous = () => env.unauthenticatedContext().firestore();

/** A document written by GitHub (the service account skips the rules). */
async function seed(path, data) {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), path), data));
}

test("il proprietario legge e scrive le sue liste", async () => {
    await assertSucceeds(setDoc(doc(owner(), "artisti/12948083"), { nome: "Ava Max", lista: "controllare" }));
    await assertSucceeds(getDoc(doc(owner(), "artisti/12948083")));
    await assertSucceeds(deleteDoc(doc(owner(), "artisti/12948083")));
});

test("il proprietario legge quello che scrive GitHub", async () => {
    await seed("stato/github", { ultimo_contatto: new Date() });
    await assertSucceeds(getDoc(doc(owner(), "stato/github")));
});

test("un altro account Google non legge e non scrive niente", async () => {
    await seed("artisti/12948083", { nome: "Ava Max" });
    await assertFails(getDoc(doc(stranger(), "artisti/12948083")));
    await assertFails(setDoc(doc(stranger(), "artisti/1"), { nome: "Intruso" }));
    await assertFails(getDoc(doc(stranger(), "stato/github")));
});

test("chi non ha fatto l'accesso non legge e non scrive niente", async () => {
    await seed("artisti/12948083", { nome: "Ava Max" });
    await assertFails(getDoc(doc(anonymous(), "artisti/12948083")));
    await assertFails(setDoc(doc(anonymous(), "artisti/1"), { nome: "Intruso" }));
});

test("con le regole non ancora pubblicate nessuno entra, nemmeno il proprietario", async () => {
    const locked = await initializeTestEnvironment({
        projectId: "demo-cns-chiuso",
        firestore: { rules: template }, // emulator address from FIRESTORE_EMULATOR_HOST
    });
    try {
        // (A Google account's code is 28 letters and digits, so it can never be "__OWNER_UID__")
        await assertFails(getDoc(doc(locked.authenticatedContext(OWNER).firestore(), "artisti/1")));
        await assertFails(setDoc(doc(locked.authenticatedContext(OWNER).firestore(), "artisti/1"), { nome: "X" }));
    } finally {
        await locked.cleanup();
    }
});
