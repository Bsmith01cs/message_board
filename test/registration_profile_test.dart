import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_board/screens/register_screen.dart';
import 'package:message_board/services/user_record_service.dart';
import 'package:message_board/screens/board_screen.dart';
import 'package:message_board/widgets/auth_gate.dart';
import 'package:message_board/widgets/profile_gate.dart';

import 'fakes.dart';

void main() {
  late FakeAuthService auth;
  late FakeUserRecordService records;
  late FakeBoardService board;

  setUp(() {
    auth = FakeAuthService();
    records = FakeUserRecordService();
    board = FakeBoardService()..initial = const [];
  });
  tearDown(() {
    auth.authStateController.close();
    records.disposeControllers();
    board.dispose();
  });

  Future<void> fillForm(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).at(0), '  Ada ');
    await tester.enterText(find.byType(TextFormField).at(1), ' Lovelace ');
    await tester.enterText(
      find.byType(TextFormField).at(2),
      ' ada@example.com ',
    );
    await tester.enterText(find.byType(TextFormField).at(3), 'secret123');
    await tester.enterText(find.byType(TextFormField).at(4), 'secret123');
  }

  Widget standaloneRegister() => MaterialApp(
    home: RegisterScreen(
      authService: auth,
      userRecordService: records,
      onShowLogin: () {},
    ),
  );

  testWidgets('registration writes a five-field profile keyed by the Auth uid',
      (tester) async {
    await tester.pumpWidget(standaloneRegister());
    await fillForm(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Register'));
    await tester.pumpAndSettle();

    expect(auth.registerCalls, 1);
    expect(auth.lastEmail, 'ada@example.com');
    expect(records.saveCalls, 1);

    // FakeUser().uid is what FakeAuthService returns from register().
    expect(records.lastWriteUid, 'test-uid');

    final written = records.lastWrite!;
    expect(written.keys.toSet(), requiredUserFields.toSet());
    expect(written['uid'], 'test-uid');
    expect(written['firstName'], 'Ada');
    expect(written['lastName'], 'Lovelace');
    expect(written['role'], defaultUserRole);
    expect(written['registrationDateTime'], FieldValue.serverTimestamp());
  });

  testWidgets(
    'names survive registration even when AuthGate disposes the screen first',
    (tester) async {
      records.seed('test-uid', null);
      auth.pending = Completer<UserCredential>();

      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            authService: auth,
            userRecordService: records,
            boardService: board,
            authState: auth.authStateController.stream,
          ),
        ),
      );
      auth.authStateController.add(null);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create an account'));
      await tester.pumpAndSettle();
      await fillForm(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Register'));
      await tester.pump();

      expect(auth.registerCalls, 1);
      expect(records.saveCalls, 0);

      // Firebase auto-signs-in the new user: AuthGate rebuilds and the
      // RegisterScreen (and its controllers) are disposed mid-flight.
      auth.authStateController.add(FakeUser());
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsNothing);
      expect(find.byType(CompleteProfileScreen), findsOneWidget);

      // The registration future continues and still has the captured names.
      auth.pending!.complete(FakeUserCredential(FakeUser()));
      await tester.pumpAndSettle();

      expect(records.saveCalls, 1);
      expect(records.lastWrite!['firstName'], 'Ada');
      expect(records.lastWrite!['lastName'], 'Lovelace');
    },
  );

  testWidgets('a failed profile write does not create a second account', (
    tester,
  ) async {
    records.saveFailure = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'unavailable',
    );

    await tester.pumpWidget(standaloneRegister());
    await fillForm(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Register'));
    await tester.pumpAndSettle();

    expect(auth.registerCalls, 1);
    expect(records.saveCalls, 1);
    expect(
      find.text('No internet connection. Please try again.'),
      findsOneWidget,
    );

    // The button now retries only the profile write.
    expect(
      find.widgetWithText(FilledButton, 'Retry Profile Setup'),
      findsOneWidget,
    );

    records.saveFailure = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Retry Profile Setup'));
    await tester.pumpAndSettle();

    expect(auth.registerCalls, 1, reason: 'no second Firebase account');
    expect(records.saveCalls, 2);
    expect(records.documents['test-uid']!['firstName'], 'Ada');
  });

  testWidgets('auth failures are shown and no profile is written', (
    tester,
  ) async {
    auth.failure = FirebaseAuthException(code: 'email-already-in-use');

    await tester.pumpWidget(standaloneRegister());
    await fillForm(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Register'));
    await tester.pumpAndSettle();

    expect(
      find.text('An account already exists for that email.'),
      findsOneWidget,
    );
    expect(records.saveCalls, 0);
    expect(find.textContaining('email-already-in-use'), findsNothing);
  });

  testWidgets('signing in with an existing profile does not rewrite it', (
    tester,
  ) async {
    records.documents['test-uid'] = {
      'uid': 'test-uid',
      'firstName': 'Original',
      'lastName': 'Name',
      'role': defaultUserRole,
      'registrationDateTime': Timestamp.fromDate(DateTime.utc(2020)),
    };
    records.seed('test-uid', completeRecord(firstName: 'Original'));

    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          authService: auth,
          userRecordService: records,
          boardService: board,
          authState: auth.authStateController.stream,
        ),
      ),
    );
    auth.authStateController.add(FakeUser());
    await tester.pumpAndSettle();

    expect(find.byType(BoardScreen), findsOneWidget);
    expect(records.saveCalls, 0, reason: 'login must not write the profile');
    expect(records.documents['test-uid']!['firstName'], 'Original');
  });

  testWidgets('switching users does not reuse the previous profile state', (
    tester,
  ) async {
    records.seed('test-uid', completeRecord());
    records.seed('second-uid', null);

    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          authService: auth,
          userRecordService: records,
          boardService: board,
          authState: auth.authStateController.stream,
        ),
      ),
    );

    auth.authStateController.add(FakeUser());
    await tester.pumpAndSettle();
    expect(find.byType(BoardScreen), findsOneWidget);

    auth.authStateController.add(FakeUser(uid: 'second-uid'));
    await tester.pumpAndSettle();

    // The second user has no profile, so they must not inherit board access.
    expect(find.byType(BoardScreen), findsNothing);
    expect(find.byType(CompleteProfileScreen), findsOneWidget);
  });
}
