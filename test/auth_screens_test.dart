import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_board/screens/login_screen.dart';
import 'package:message_board/screens/register_screen.dart';
import 'package:message_board/screens/board_screen.dart';
import 'package:message_board/widgets/auth_flow.dart';

import 'fakes.dart';

void main() {
  late FakeAuthService auth;
  late FakeUserRecordService records;

  setUp(() {
    auth = FakeAuthService();
    records = FakeUserRecordService();
  });
  tearDown(() {
    auth.authStateController.close();
    records.disposeControllers();
  });

  Widget host(Widget child) => MaterialApp(home: child);

  testWidgets('registration form renders every required field', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(RegisterScreen(
        authService: auth,
        userRecordService: records,
        onShowLogin: () {},
      )),
    );

    expect(find.text('First name'), findsOneWidget);
    expect(find.text('Last name'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Register'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
  });

  testWidgets('empty registration form shows required-field messages', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(RegisterScreen(
        authService: auth,
        userRecordService: records,
        onShowLogin: () {},
      )),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Register'));
    await tester.pump();

    expect(find.text('Enter your first name'), findsOneWidget);
    expect(find.text('Enter your last name'), findsOneWidget);
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter a password'), findsOneWidget);
    expect(auth.registerCalls, 0);
  });

  testWidgets('mismatched passwords block registration', (tester) async {
    await tester.pumpWidget(
      host(RegisterScreen(
        authService: auth,
        userRecordService: records,
        onShowLogin: () {},
      )),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Lovelace');
    await tester.enterText(
      find.byType(TextFormField).at(2),
      '  ada@example.com  ',
    );
    await tester.enterText(find.byType(TextFormField).at(3), 'secret123');
    await tester.enterText(find.byType(TextFormField).at(4), 'secret124');

    await tester.tap(find.widgetWithText(FilledButton, 'Register'));
    await tester.pump();

    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(auth.registerCalls, 0);
  });

  testWidgets('short password is rejected', (tester) async {
    await tester.pumpWidget(
      host(RegisterScreen(
        authService: auth,
        userRecordService: records,
        onShowLogin: () {},
      )),
    );

    await tester.enterText(find.byType(TextFormField).at(3), 'abc');
    await tester.tap(find.widgetWithText(FilledButton, 'Register'));
    await tester.pump();

    expect(find.text('Use at least 6 characters'), findsOneWidget);
  });

  testWidgets('login form renders', (tester) async {
    await tester.pumpWidget(
      host(LoginScreen(authService: auth, onShowRegister: () {})),
    );

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign In'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
  });

  testWidgets('invalid email shows feedback and does not call AuthService', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(LoginScreen(authService: auth, onShowRegister: () {})),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'not-an-email');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pump();

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(auth.signInCalls, 0);
  });

  testWidgets('sign-in button is disabled while the request is in flight', (
    tester,
  ) async {
    auth.pending = Completer<UserCredential>();

    await tester.pumpWidget(
      host(LoginScreen(authService: auth, onShowRegister: () {})),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'ada@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pump();

    expect(auth.signInCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);

    // A second tap while loading must not start another request.
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(auth.signInCalls, 1);

    auth.pending!.complete(FakeUserCredential(FakeUser()));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Sign In'), findsOneWidget);
  });

  testWidgets('email is trimmed before reaching AuthService', (tester) async {
    await tester.pumpWidget(
      host(LoginScreen(authService: auth, onShowRegister: () {})),
    );

    await tester.enterText(
      find.byType(TextFormField).at(0),
      '  ada@example.com ',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(auth.lastEmail, 'ada@example.com');
  });

  testWidgets('Firebase errors are shown as friendly text', (tester) async {
    auth.failure = FirebaseAuthException(code: 'wrong-password');

    await tester.pumpWidget(
      host(LoginScreen(authService: auth, onShowRegister: () {})),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'ada@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect email or password.'), findsOneWidget);
    expect(find.textContaining('wrong-password'), findsNothing);
    // The obscured password field still holds the typed text; what matters is
    // that no displayed label or message repeats it.
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').contains('secret123'),
      ),
      findsNothing,
    );
  });

  testWidgets('users can switch between login and registration', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(AuthFlow(authService: auth, userRecordService: records)),
    );

    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);

    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('the board screen sign out action calls AuthService', (
    tester,
  ) async {
    final board = FakeBoardService()..initial = const [];
    addTearDown(board.dispose);

    await tester.pumpWidget(
      host(
        BoardScreen(
          author: completeRecord(),
          authService: auth,
          boardService: board,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sign Out'));
    await tester.pumpAndSettle();

    expect(auth.signOutCalls, 1);
  });
}
