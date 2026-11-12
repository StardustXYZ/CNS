// Firebase for CNS: Google sign-in and Firestore.
// The SDK is loaded when needed from Google's servers (the service worker keeps a copy for
// offline use): if it cannot be loaded, the app still opens and just says so.
// The configuration below is public by design: the data is protected by the rules in
// firebase/firestore.rules, which let only the owner's account in.

const SDK = "https://www.gstatic.com/firebasejs/13.1.0";
const CONFIG = {
    apiKey: "AIzaSyD89BjWgi1hN7n0xfYn7PWe2IZYjMuyrSY",
    authDomain: "cns-chi-ni-sindimu.firebaseapp.com",
    projectId: "cns-chi-ni-sindimu",
    storageBucket: "cns-chi-ni-sindimu.firebasestorage.app",
    messagingSenderId: "1028113740311",
    appId: "1:1028113740311:web:1baa676d710412e7a52252",
};
// On this PC with "?emulatore" in the address, the local emulators instead of the real Firebase
const USE_EMULATORS = ["localhost", "127.0.0.1"].includes(location.hostname) && new URLSearchParams(location.search).has("emulatore");

let sdk = null; // { auth, db, modules }

/** Load the SDK and start Firebase; ``onUser`` is called with the signed-in user (or null) at every change. */
export async function startFirebase(onUser) {
    const [appMod, authMod, storeMod] = await Promise.all([
        import(`${SDK}/firebase-app.js`),
        import(`${SDK}/firebase-auth.js`),
        import(`${SDK}/firebase-firestore.js`),
    ]);
    const app = appMod.initializeApp(USE_EMULATORS ? { ...CONFIG, projectId: "demo-cns", apiKey: "demo" } : CONFIG);
    const auth = authMod.getAuth(app);
    auth.languageCode = "it";
    // The lists stay on the phone too, so the app shows them without connection
    const db = USE_EMULATORS
        ? storeMod.getFirestore(app)
        : storeMod.initializeFirestore(app, { localCache: storeMod.persistentLocalCache({ tabManager: storeMod.persistentMultipleTabManager() }) });
    if (USE_EMULATORS) {
        authMod.connectAuthEmulator(auth, "http://localhost:9099", { disableWarnings: true });
        storeMod.connectFirestoreEmulator(db, "localhost", 8181);
    }
    sdk = { auth, db, authMod, storeMod };
    authMod.onAuthStateChanged(auth, (user) => onUser(user ? {
        uid: user.uid, name: user.displayName || "", email: user.email || "", photo: user.photoURL || "",
    } : null));
}

/** Google sign-in in a popup (redirects break when the sign-in page is on another site). */
export async function signIn() {
    const { auth, authMod } = sdk;
    const provider = new authMod.GoogleAuthProvider();
    provider.setCustomParameters({ prompt: "select_account" });
    await authMod.signInWithPopup(auth, provider);
}

export async function signOutUser() {
    await sdk.authMod.signOut(sdk.auth);
}

/** Follow a document: ``onData(fields | null)`` at every change, ``onError(error)`` if refused. Returns a stop function. */
export function watchDocument(path, onData, onError) {
    const { db, storeMod } = sdk;
    return storeMod.onSnapshot(storeMod.doc(db, path), (snap) => onData(snap.exists() ? snap.data() : null), onError);
}

/** Firebase's error codes as a sentence in Italian. */
export function explainError(err) {
    const code = err?.code || "";
    if (code === "permission-denied") {
        return "Accesso negato: le regole di Firebase non contengono ancora il tuo codice utente.";
    }
    if (code === "auth/popup-blocked") return "Il browser ha bloccato la finestra di accesso: consenti i popup e riprova.";
    if (code === "auth/popup-closed-by-user" || code === "auth/cancelled-popup-request") return "Accesso annullato.";
    if (code === "auth/unauthorized-domain") return "Questo indirizzo non è tra i domini autorizzati di Firebase.";
    if (code === "auth/network-request-failed" || code === "unavailable") return "Nessuna connessione: riprova quando sei online.";
    return `Errore di Firebase (${code || err?.message || "sconosciuto"}).`;
}
