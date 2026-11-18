# CNS – app Android

L'app Android di CNS, scritta in Flutter. Legge e scrive gli stessi dati di Firebase
dell'app web, così le due funzionano insieme.

## Cosa serve sul PC

- Flutter 3.35 (Dart 3.9) e Java 21
- Android SDK con build-tools 36
- In `Desktop\cns-chiavi`: `google-services.json` (da Firebase), la chiave di firma
  `cns-firma.jks` e `key.properties` (le sue password). Prima di costruire l'APK,
  `google-services.json` va copiato in `android/app/` e `key.properties` in `android/`.

## Comandi, dalla cartella `mobile/`

```
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

L'APK si trova in `build/app/outputs/flutter-apk/app-release.apk`, firmato con la chiave
definitiva di `key.properties`. Senza quel file la costruzione si ferma con un avviso: un APK
firmato con la chiave di prova non si può pubblicare, perché chi ha già la versione vera non
potrebbe aggiornarlo. Per un APK di prova solo per te, sul PC: `CNS_FIRMA_DI_PROVA=1` prima
di `flutter build apk --release` (in PowerShell: `$env:CNS_FIRMA_DI_PROVA = "1"`).

## Pubblicare una versione

1. In `pubspec.yaml` alza la versione, per esempio da `1.0.0+10` a `1.0.1+11`: il primo
   numero è quello che vede chi installa, il secondo va aumentato a ogni APK, altrimenti
   Android non lo installa sopra il vecchio.
2. Costruisci l'APK firmato e provalo sul telefono.
3. Su GitHub: **Releases** → **Draft a new release** → tag `app-v1.0.1` (crealo al momento) →
   titolo `CNS 1.0.1` → due righe con le novità → trascina l'APK, rinominato `cns-1.0.1.apk` →
   lascia spento **Set as a pre-release** → **Publish release**.
4. Le app già installate controllano le release all'apertura e mostrano l'avviso
   «È uscita la versione 1.0.1 di CNS».

## Icone

Le icone (classica, adattiva, a tema e quella bianca delle notifiche) si disegnano con lo
stesso programma delle icone del web, dalla cartella principale del progetto:

```
python tools/crea_icone.py
```

## Mai nel repository

`google-services.json`, `key.properties` e i file `.jks` restano solo sul PC
(in `Desktop\cns-chiavi`) e sono esclusi da `.gitignore`. Se la chiave di firma si perde,
le app già installate non si possono più aggiornare: tienine una copia al sicuro.
