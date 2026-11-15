# CNS – app Android

L'app Android di CNS, scritta in Flutter. Legge e scrive gli stessi dati di Firebase
dell'app web, così le due funzionano insieme.

## Cosa serve sul PC

- Flutter 3.35 (Dart 3.9) e Java 21
- Android SDK con build-tools 36

## Comandi, dalla cartella `mobile/`

```
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

L'APK di prova si trova in `build/app/outputs/flutter-apk/app-debug.apk`.

## Icone

Le icone (classica, adattiva, a tema e quella bianca delle notifiche) si disegnano con lo
stesso programma delle icone del web, dalla cartella principale del progetto:

```
python tools/crea_icone.py
```

## Mai nel repository

`google-services.json`, `key.properties` e i file `.jks` restano solo sul PC
(in `Desktop\cns-chiavi`) e sono esclusi da `.gitignore`.
