import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_board/screens/login_screen.dart';
import 'package:message_board/screens/board_screen.dart';
import 'package:message_board/widgets/auth_gate.dart';

import 'fakes.dart';

void main() {
  late FakeAuthService auth;
  late FakeUserRecordService records;
  late FakeBoardService board;

  setUp(() {
    auth = FakeAuthService();
    records = FakeUserRecordService();
    board = FakeBoardService()..initial = const [];
    // A complete profile, so AuthGate's signed-in branch reaches the
    // placeholder instead of stopping at the profile form.
    records.seed('test-uid', completeRecord());
  });
  tearDown(() {
    auth.authStateController.close();
    records.disposeControllers();
    board.dispose();
  });

  Widget wrap(Stream<User?> authState) => MaterialApp(
    home: AuthGate(
      authService: auth,
      userRecordService: records,
      boardService: board,
      authState: authState,
    ),
  );

  testWidgets('loading state shows a progress indicator', (tester) async {
    final controller = StreamController<User?>();
    addTearDown(controller.close);

    await tester.pumpWidget(wrap(controller.stream));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('signed-out state shows the login screen', (tester) async {
    await tester.pumpWidget(wrap(Stream<User?>.value(null)));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign In'), findsOneWidget);
  });

  testWidgets('signed-in state with a complete profile shows the board', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(Stream<User?>.value(FakeUser())));
    await tester.pumpAndSettle();

    expect(find.byType(BoardScreen), findsOneWidget);
    expect(find.text('Signed in as Ada Lovelace'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('sign-out returns the user to the login screen', (tester) async {
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

    await tester.tap(find.byTooltip('Sign Out'));
    auth.authStateController.add(null);
    await tester.pumpAndSettle();

    expect(auth.signOutCalls, 1);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('stream error shows a safe message with no Firebase details', (
    tester,
  ) async {
    final failing = Stream<User?>.error(
      FirebaseAuthException(code: 'network-request-failed'),
    );

    await tester.pumpWidget(wrap(failing));
    await tester.pump();

    expect(find.text('Sign-in is unavailable'), findsOneWidget);
    expect(find.textContaining('network-request-failed'), findsNothing);
    expect(find.textContaining('FirebaseAuthException'), findsNothing);
  });
}
