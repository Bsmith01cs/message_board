import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_board/services/user_record_service.dart';
import 'package:message_board/widgets/profile_gate.dart';

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

  Widget gate() => MaterialApp(
    home: ProfileGate(
      uid: 'test-uid',
      authService: auth,
      userRecordService: records,
      signedInBuilder: (_, record) =>
          Scaffold(body: Text('BOARD ${record.firstName}')),
    ),
  );

  testWidgets('a complete profile reaches the protected screen', (
    tester,
  ) async {
    records.seed('test-uid', completeRecord());

    await tester.pumpWidget(gate());
    await tester.pumpAndSettle();

    expect(find.textContaining('BOARD'), findsOneWidget);
    expect(find.byType(CompleteProfileScreen), findsNothing);
  });

  testWidgets('a missing profile cannot reach the protected screen', (
    tester,
  ) async {
    records.seed('test-uid', null);

    await tester.pumpWidget(gate());
    await tester.pumpAndSettle();

    expect(find.textContaining('BOARD'), findsNothing);
    expect(find.byType(CompleteProfileScreen), findsOneWidget);
    expect(find.text('Your profile is incomplete'), findsOneWidget);
  });

  testWidgets('an incomplete profile requires completion and prefills', (
    tester,
  ) async {
    records.seed(
      'test-uid',
      const UserRecord(
        uid: 'test-uid',
        firstName: 'Ada',
        lastName: '',
        role: defaultUserRole,
        registrationDateTime: null,
      ),
    );

    await tester.pumpWidget(gate());
    await tester.pumpAndSettle();

    expect(find.textContaining('BOARD'), findsNothing);
    expect(find.byType(CompleteProfileScreen), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
  });

  testWidgets('loading shows a progress indicator', (tester) async {
    await tester.pumpWidget(gate());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('BOARD'), findsNothing);
  });

  testWidgets('saving the profile promotes the user automatically', (
    tester,
  ) async {
    records.seed('test-uid', null);

    await tester.pumpWidget(gate());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Lovelace');
    await tester.tap(find.text('Save Profile'));
    await tester.pumpAndSettle();

    expect(records.saveCalls, 1);
    expect(records.lastWriteUid, 'test-uid');
    expect(records.lastWrite!['firstName'], 'Ada');

    // The document listener, not a manual navigation, moves the user on.
    records.emit('test-uid', completeRecord());
    await tester.pumpAndSettle();
    expect(find.textContaining('BOARD'), findsOneWidget);
  });

  testWidgets('empty names are rejected before any write', (tester) async {
    records.seed('test-uid', null);

    await tester.pumpWidget(gate());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Profile'));
    await tester.pump();

    expect(find.text('Enter your first name'), findsOneWidget);
    expect(find.text('Enter your last name'), findsOneWidget);
    expect(records.saveCalls, 0);
  });

  testWidgets('a failed write shows an error and can be retried', (
    tester,
  ) async {
    records.seed('test-uid', null);
    records.saveFailure = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'unavailable',
    );

    await tester.pumpWidget(gate());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Lovelace');
    await tester.tap(find.text('Save Profile'));
    await tester.pumpAndSettle();

    expect(find.text('No internet connection. Please try again.'), findsOneWidget);
    expect(find.textContaining('BOARD'), findsNothing);
    expect(records.saveCalls, 1);

    // The button is live again, so the write can be retried.
    records.saveFailure = null;
    await tester.tap(find.text('Save Profile'));
    await tester.pumpAndSettle();
    expect(records.saveCalls, 2);
    expect(records.documents['test-uid'], isNotNull);
  });

  testWidgets('permission-denied is reported safely, not as a missing profile',
      (tester) async {
    records.watchFailure = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );

    await tester.pumpWidget(gate());
    await tester.pumpAndSettle();

    expect(find.byType(ProfileErrorScreen), findsOneWidget);
    expect(find.byType(CompleteProfileScreen), findsNothing);
    expect(find.textContaining('BOARD'), findsNothing);
    expect(find.textContaining('permission-denied'), findsNothing);
    expect(find.textContaining('FirebaseException'), findsNothing);
  });

  testWidgets('the profile error screen can sign out', (tester) async {
    records.watchFailure = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );

    await tester.pumpWidget(gate());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();

    expect(auth.signOutCalls, 1);
  });

  testWidgets('an existing complete profile is not overwritten', (
    tester,
  ) async {
    records.documents['test-uid'] = {
      'uid': 'test-uid',
      'firstName': 'Original',
      'lastName': 'Name',
      'role': 'admin',
      'registrationDateTime': Timestamp.fromDate(DateTime.utc(2020)),
    };
    records.seed('test-uid', null);

    await tester.pumpWidget(gate());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Replacement');
    await tester.enterText(find.byType(TextFormField).at(1), 'Attempt');
    await tester.tap(find.text('Save Profile'));
    await tester.pumpAndSettle();

    expect(records.saveCalls, 1);
    expect(records.documents['test-uid']!['firstName'], 'Original');
    expect(records.documents['test-uid']!['role'], 'admin');
    expect(
      records.documents['test-uid']!['registrationDateTime'],
      Timestamp.fromDate(DateTime.utc(2020)),
    );
  });
}
