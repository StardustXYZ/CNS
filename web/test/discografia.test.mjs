// Discography: merged versions, kinds, order. Titles taken from Deezer (November 2026).
import assert from "node:assert/strict";
import { test } from "node:test";
import {
    arrange, baseTitle, countKinds, dateLabel, groupReleases, isFeaturing, kindOf, releaseFromApi, spotifySearchUrl,
} from "../discografia.js";

let next = 1;
const rel = (title, date, type = "single") => releaseFromApi({ id: next++, title, release_date: date, record_type: type });

test("titolo senza le parole delle versioni", () => {
    assert.equal(baseTitle("Sweet but Psycho (Leon Lour Remix)"), "Sweet but Psycho");
    assert.equal(baseTitle("Sweet but Psycho (The Remixes)"), "Sweet but Psycho");
    assert.equal(baseTitle("So Am I (Analog Acoustic)"), "So Am I");
    assert.equal(baseTitle("So Am I (Steve Void Extended Mix)"), "So Am I");
    assert.equal(baseTitle("So Am I (feat. NCT 127)"), "So Am I");
    assert.equal(baseTitle("Torn (Cirkut DJ Mix)"), "Torn");
    assert.equal(baseTitle("Born This Way (International Special Edition Version)"), "Born This Way");
    assert.equal(baseTitle("Chromatica [Deluxe]"), "Chromatica");
    assert.equal(baseTitle("Alone, Pt. II (Live at Château de Fontainebleau)"), "Alone, Pt. II");
    assert.equal(baseTitle("Heaven & Hell - Deluxe Edition"), "Heaven & Hell");
    // Not versions: they stay as they are
    assert.equal(baseTitle("Top Gun: Maverick (Music From The Motion Picture)"), "Top Gun: Maverick (Music From The Motion Picture)");
    assert.equal(baseTitle("Arcane League of Legends (Soundtrack from the Animated Series)"), "Arcane League of Legends (Soundtrack from the Animated Series)");
    assert.equal(baseTitle("(Remix)"), "(Remix)"); // nothing would be left
});

test("featuring solo se il nome dell'artista è tra gli ospiti", () => {
    assert.equal(isFeaturing("BURN (feat. Ava Max)", "Ava Max"), true);
    assert.equal(isFeaturing("Brought The Heat Back (Feat. Ava Max)", "Ava Max"), true);
    assert.equal(isFeaturing("Duet (with Ava Max)", "Ava Max"), true);
    assert.equal(isFeaturing("Kings & Queens, Pt. 2 (feat. Lauv & Saweetie)", "Ava Max"), false);
    assert.equal(isFeaturing("Song (feat. Ava Maxwell)", "Ava Max"), false);
    assert.equal(kindOf(rel("BURN (feat. Ava Max)", "2026-10-09"), "Ava Max"), "featuring");
    assert.equal(kindOf(rel("Heaven & Hell", "2020-09-18", "album"), "Ava Max"), "album");
});

test("i remix e le versioni finiscono sotto l'originale", () => {
    const groups = groupReleases([
        rel("Sweet but Psycho (Paul Morrell Remix)", "2018-08-15"),
        rel("Sweet but Psycho (Acoustic)", "2018-08-15"),
        rel("Sweet but Psycho", "2018-08-17"),
        rel("Sweet but Psycho (The Remixes)", "2019-03-04"),
        rel("So Am I", "2019-03-07"),
        rel("So Am I (feat. NCT 127)", "2019-07-03"),
    ], "Ava Max");
    assert.equal(groups.length, 2);
    const sweet = groups.find((g) => g.main.title === "Sweet but Psycho");
    assert.equal(sweet.date, "2018-08-17"); // the original's date, not the earlier acoustic one
    assert.equal(sweet.versions.length, 3);
    assert.equal(groups.find((g) => g.main.title === "So Am I").versions.length, 1);
});

test("album e singolo con lo stesso nome restano separati; deluxe ed explicit/clean si uniscono", () => {
    const groups = groupReleases([
        rel("Heaven & Hell", "2020-09-18", "album"),
        rel("Heaven & Hell (Deluxe)", "2021-03-01", "album"),
        rel("Heaven & Hell", "2020-09-18", "album"), // the clean copy: same title
        rel("Heaven & Hell", "2020-08-01", "single"),
    ], "Ava Max");
    assert.equal(groups.length, 2);
    const album = groups.find((g) => g.kind === "album");
    assert.equal(album.versions.length, 2);
});

test("un EP e la sua versione deluxe album sono la stessa uscita", () => {
    const groups = groupReleases([rel("Diamonds & Dancefloors (Deluxe)", "2023-05-01", "album"), rel("Diamonds & Dancefloors", "2023-01-27", "ep")], "Ava Max");
    assert.equal(groups.length, 1);
    assert.equal(groups[0].kind, "ep");
    assert.equal(groups[0].main.title, "Diamonds & Dancefloors");
});

test("conteggio per tipo e ordine per data", () => {
    const groups = groupReleases([
        rel("Uno", "2018-04-20"), rel("Due", "2020-01-01", "album"), rel("Tre", ""), rel("Quattro", "2026-11-06"),
        rel("BURN (feat. Ava Max)", "2026-10-09"),
    ], "Ava Max");
    assert.deepEqual(countKinds(groups), { single: 3, album: 1, featuring: 1 });
    assert.deepEqual(arrange(groups).map((g) => g.main.title), ["Quattro", "BURN (feat. Ava Max)", "Due", "Uno", "Tre"]);
    assert.deepEqual(arrange(groups, "", true).map((g) => g.main.title), ["Uno", "Due", "BURN (feat. Ava Max)", "Quattro", "Tre"]);
    assert.deepEqual(arrange(groups, "single", true).map((g) => g.main.title), ["Uno", "Quattro", "Tre"]);
});

test("date, link di Spotify e dati di Deezer", () => {
    assert.equal(dateLabel("2026-11-06"), "06/11/2026");
    assert.equal(dateLabel(""), "data sconosciuta");
    assert.equal(spotifySearchUrl("K/DA", "MORE"), "https://open.spotify.com/search/K%2FDA%20MORE");
    const r = releaseFromApi({ id: 5, title: "X", release_date: "0000-00-00", record_type: "EP", cover_medium: "c", explicit_lyrics: true });
    assert.deepEqual(r, { id: "5", title: "X", type: "ep", date: "", cover: "c", link: "https://www.deezer.com/album/5", explicit: true });
});
