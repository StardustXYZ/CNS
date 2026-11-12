// Pure functions of web/deezer.js (no network). Run with: node --test web/test/
import assert from "node:assert/strict";
import { test } from "node:test";
import { artistFromApi, artistIdFromLink, fansLabel, normalize, rankArtists } from "../deezer.js";

test("normalize ignora maiuscole, accenti e punteggiatura", () => {
    assert.equal(normalize("Beyoncé"), "beyonce");
    assert.equal(normalize("  K/DA "), "k da");
    assert.equal(normalize("Isabel LaRosa"), "isabel larosa");
});

test("codice artista dai link di Deezer", () => {
    assert.equal(artistIdFromLink("https://www.deezer.com/it/artist/12948083?utm_source=x"), "12948083");
    assert.equal(artistIdFromLink("https://www.deezer.com/artist/15741"), "15741");
    assert.equal(artistIdFromLink("guarda https://www.deezer.com/en-gb/artist/1182 !"), "1182");
    assert.equal(artistIdFromLink("https://www.deezer.com/it/album/1139685681"), null);
    assert.equal(artistIdFromLink("Ava Max"), null);
});

test("prima il nome identico con più fan, poi l'ordine di Deezer", () => {
    const results = [
        { id: "1", name: "Amy Lee", fans: 153 },
        { id: "2", name: "AmyLee", fans: 264 },
        { id: "5", name: "Amy Lee", fans: 265225 },
        { id: "6", name: "Amy Leeman", fans: 62 },
    ];
    assert.deepEqual(rankArtists("amy lee", results).map((a) => a.id), ["5", "1", "2", "6"]);
    assert.deepEqual(rankArtists("Nessuno", results).map((a) => a.id), ["1", "2", "5", "6"]);
});

test("numero di fan in italiano", () => {
    assert.equal(fansLabel(1235611), "1,2 mln di fan");
    assert.equal(fansLabel(136074), "136.074 fan");
    assert.equal(fansLabel(1), "1 fan");
});

test("artista dalla risposta di Deezer", () => {
    const a = artistFromApi({ id: 12948083, name: "Ava Max", nb_fan: 1235611, nb_album: 114, picture_big: "https://cdn/ava.jpg" });
    assert.deepEqual(a, { id: "12948083", name: "Ava Max", picture: "https://cdn/ava.jpg", fans: 1235611, albums: 114, link: "https://www.deezer.com/artist/12948083" });
});
