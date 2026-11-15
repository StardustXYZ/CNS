import 'package:cns/data/account.dart';
import 'package:cns/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_account.dart';

void main() {
  group("l'account", () {
    test("Google: ammesso, e l'amministratore riceve la lista", () async {
      final backend = FakeBackend();
      final store = AccountStore(backend);
      await store.signInWithGoogle();
      await settle();
      expect(store.user!.email, 'Capo@gmail.com');
      expect(store.admission, Admission.admitted);
      expect(store.isAdmin, isTrue);
      expect(store.allowed, ['amico@example.com']);
      await settle();
      expect(backend.remembered['capo'], 'capo@gmail.com'); // in minuscolo, come nell'app web
      await store.signOut();
      await settle();
      expect(store.user, isNull);
      expect(store.admission, Admission.none);
      expect(store.isAdmin, isFalse);
    });

    test("un account nuovo con email aspetta la conferma, poi viene controllato", () async {
      final backend = FakeBackend()..allowed.add('nuovo@example.com');
      final store = AccountStore(backend);
      await store.register('nuovo@example.com', 'password1');
      await settle();
      expect(backend.sent, ['conferma:nuovo@example.com']);
      expect(store.user!.verified, isFalse);
      expect(store.admission, Admission.none);
      expect(await store.reloadVerified(), isFalse); // non ancora confermata
      backend.verifiedEmails.add('nuovo@example.com');
      expect(await store.reloadVerified(), isTrue);
      await settle();
      expect(store.admission, Admission.admitted);
      expect(store.isAdmin, isFalse);
    });

    test('chi non è nella lista resta fuori', () async {
      final backend = FakeBackend()
        ..accounts['estraneo@example.com'] = 'password1'
        ..verifiedEmails.add('estraneo@example.com');
      final store = AccountStore(backend);
      await store.signInWithEmail('estraneo@example.com', 'password1');
      await settle();
      expect(store.admission, Admission.notAdmitted);
      expect(backend.remembered, isEmpty);
    });

    test('password sbagliata: errore con parole chiare', () async {
      final store = AccountStore(FakeBackend());
      expect(
        () => store.signInWithEmail('amico@example.com', 'sbagliata'),
        throwsA(isA<AccountError>().having((e) => e.message, 'message', 'Email o password sbagliate.')),
      );
    });

    test('senza connessione il controllo dà errore, e "Riprova" funziona', () async {
      final backend = FakeBackend()..offline = true;
      final store = AccountStore(backend);
      await store.signInWithEmail('amico@example.com', 'segreta1');
      await settle();
      expect(store.admission, Admission.error);
      backend.offline = false;
      await store.checkAdmission();
      expect(store.admission, Admission.admitted);
    });

    test("la lista degli ammessi: minuscolo, senza doppioni, in ordine", () async {
      final backend = FakeBackend();
      final store = AccountStore(backend);
      await store.signInWithGoogle();
      await settle();
      await store.setAllowList(['Zeta@Example.com', 'amico@example.com', ' amico@example.com ', '']);
      expect(backend.allowed, ['amico@example.com', 'zeta@example.com']);
      expect(store.allowed, backend.allowed);
    });

    test('senza Firebase l’accesso non è disponibile', () async {
      final store = AccountStore(null);
      expect(store.available, isFalse);
      expect(() => store.signInWithGoogle(), throwsA(isA<AccountError>()));
    });

    test("l'email deve sembrare un indirizzo", () {
      expect(looksLikeEmail('amico@example.com'), isTrue);
      expect(looksLikeEmail(' amico@example.com '), isTrue);
      expect(looksLikeEmail('amico@example'), isFalse);
      expect(looksLikeEmail('amico example.com'), isFalse);
    });
  });

  group("la schermata d'accesso", () {
    Future<FakeBackend> openApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(375 * 3, 812 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final backend = FakeBackend();
      await tester.pumpWidget(CnsApp(account: AccountStore(backend)));
      return backend;
    }

    testWidgets('senza account: i due modi di accesso, e niente menu', (tester) async {
      await openApp(tester);
      expect(find.text('Accedi con Google'), findsOneWidget);
      expect(find.text('Accedi con email e password'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets("con Google si entra nell'app; l'amministratore vede le persone ammesse", (tester) async {
      await openApp(tester);
      await tester.tap(find.text('Accedi con Google'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Impostazioni')));
      await tester.pumpAndSettle();
      expect(find.text('Capo · Capo@gmail.com'), findsOneWidget);
      expect(find.text('Codice utente: capo'), findsOneWidget);
      await tester.tap(find.text('Persone ammesse (1)'));
      await tester.pumpAndSettle();
      expect(find.text('amico@example.com'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Nuova@Example.com');
      await tester.tap(find.text('Aggiungi'));
      await tester.pumpAndSettle();
      expect(find.text('nuova@example.com'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets("con email: chi non è nella lista vede il messaggio e il codice utente", (tester) async {
      final backend = await openApp(tester);
      backend
        ..accounts['estraneo@example.com'] = 'password1'
        ..verifiedEmails.add('estraneo@example.com');
      await tester.tap(find.text('Accedi con email e password'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'estraneo@example.com');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'password1');
      await tester.tap(find.widgetWithText(FilledButton, 'Accedi'));
      await tester.pumpAndSettle();
      expect(find.textContaining('non è tra le persone ammesse'), findsOneWidget);
      expect(find.text('Codice utente: estraneo'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets("uscire chiede conferma e riporta all'accesso", (tester) async {
      await openApp(tester);
      await tester.tap(find.text('Accedi con Google'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Impostazioni')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Esci dall’account'));
      await tester.pumpAndSettle();
      expect(find.text('Uscire dall’account?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Esci'));
      await tester.pumpAndSettle();
      expect(find.text('Accedi con Google'), findsOneWidget);
    });
  });
}
