import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_board/screens/board_screen.dart';
import 'package:message_board/services/user_record_service.dart';
import 'package:message_board/widgets/auth_gate.dart';
import 'package:message_board/widgets/profile_gate.dart';

import 'fakes.dart';

void main() {
  late FakeAuthService auth;
  late FakeBoardService board;
  late FakeUserRecordService records;

  setUp(() {
    auth = FakeAuthService()..signedInUser = FakeUser();
    board = FakeBoardService();
    records = FakeUserRecordService();
  });
  tearDown(() {
    auth.authStateController.close();
    board.dispose();
    records.disposeControllers();
  });

  Widget screen() => MaterialApp(
    home: BoardScreen(
      author: completeRecord(),
      authService: auth,
      boardService: board,
    ),
  );

  Future<void> type(WidgetTester tester, String text) =>
      tester.enterText(find.byType(TextField), text);

  testWidgets('the board screen renders its title, composer and post button', (
    tester,
  ) async {
    board.initial = const [];

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    expect(find.text('Message Board'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Post'), findsOneWidget);
    expect(find.byTooltip('Sign Out'), findsOneWidget);
  });

  testWidgets('the signed-in display name is shown', (tester) async {
    board.initial = const [];

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    expect(find.text('Signed in as Ada Lovelace'), findsOneWidget);
  });

  testWidgets('an empty board shows a deliberate empty state', (tester) async {
    board.initial = const [];

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    expect(find.text('No messages yet'), findsOneWidget);
    expect(
      find.text('Post the first message to start the board.'),
      findsOneWidget,
    );
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('loading shows a progress indicator', (tester) async {
    await tester.pumpWidget(screen());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No messages yet'), findsNothing);
  });

  testWidgets('a stream error shows safe feedback', (tester) async {
    board.streamFailure = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    expect(find.text('Could not load the board'), findsOneWidget);
    expect(find.text('You can only change your own messages.'), findsOneWidget);
    expect(find.textContaining('permission-denied'), findsNothing);
    expect(find.textContaining('FirebaseException'), findsNothing);
  });

  testWidgets('messages render in stream order with author, text and time', (
    tester,
  ) async {
    board.initial = [
      message(
        id: 'a',
        text: 'First message',
        authorName: 'Ada Lovelace',
        createdAt: DateTime.utc(2026, 1, 1, 9, 30),
      ),
      message(
        id: 'b',
        text: 'Second message',
        authorName: 'Grace Hopper',
        createdAt: DateTime.utc(2026, 1, 2, 10, 0),
      ),
    ];

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    expect(find.text('First message'), findsOneWidget);
    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(2));

    // The order on screen matches the order the stream produced.
    final texts = tester
        .widgetList<Card>(find.byType(Card))
        .map(
          (card) => (find
              .descendant(
                of: find.byWidget(card),
                matching: find.byType(Text),
              )
              .evaluate()
              .map((e) => (e.widget as Text).data)
              .toList()),
        )
        .toList();
    expect(texts.first, contains('First message'));
    expect(texts.last, contains('Second message'));
  });

  testWidgets('a pending server timestamp is shown as sending, not a crash', (
    tester,
  ) async {
    board.initial = [message(text: 'Pending post', pendingCreatedAt: true)];

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    expect(find.text('Pending post'), findsOneWidget);
    expect(find.text('Sending…'), findsOneWidget);
  });

  testWidgets('posting valid text calls BoardService exactly once', (
    tester,
  ) async {
    board.initial = const [];

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    await type(tester, '  Hello board  ');
    await tester.tap(find.widgetWithText(FilledButton, 'Post'));
    await tester.pumpAndSettle();

    expect(board.postCalls, 1);
    expect(board.lastText, '  Hello board  ');
    expect(board.lastAuthorName, 'Ada Lovelace');
  });

  testWidgets('empty and whitespace-only text cannot be posted', (
    tester,
  ) async {
    board.initial = const [];

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Post'));
    await tester.pumpAndSettle();
    expect(board.postCalls, 0);
    expect(find.text('Enter a message before posting.'), findsOneWidget);

    await type(tester, '     ');
    await tester.tap(find.widgetWithText(FilledButton, 'Post'));
    await tester.pumpAndSettle();
    expect(board.postCalls, 0);
  });

  testWidgets('a second tap while posting is ignored', (tester) async {
    board.initial = const [];
    board.pending = Completer<void>();

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    await type(tester, 'Hello');
    await tester.tap(find.widgetWithText(FilledButton, 'Post'));
    await tester.pump();

    expect(board.postCalls, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(board.postCalls, 1);

    board.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Post'), findsOneWidget);
  });

  testWidgets('a failed post keeps the typed text and shows an error', (
    tester,
  ) async {
    board.initial = const [];
    board.postFailure = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'unavailable',
    );

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    await type(tester, 'Keep me');
    await tester.tap(find.widgetWithText(FilledButton, 'Post'));
    await tester.pumpAndSettle();

    expect(
      find.text('No internet connection. Please try again.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep me',
    );
  });

  testWidgets('a successful post clears the composer', (tester) async {
    board.initial = const [];

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    await type(tester, 'Clear me');
    await tester.tap(find.widgetWithText(FilledButton, 'Post'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('a new stream emission updates the visible board', (
    tester,
  ) async {
    board.initial = const [];

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('No messages yet'), findsOneWidget);

    // The board follows Firestore; nothing is added to a local list.
    board.emit([message(text: 'Arrived live')]);
    await tester.pumpAndSettle();

    expect(find.text('Arrived live'), findsOneWidget);
    expect(find.text('No messages yet'), findsNothing);
  });

  testWidgets('sign out calls AuthService', (tester) async {
    board.initial = const [];

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sign Out'));
    await tester.pumpAndSettle();

    expect(auth.signOutCalls, 1);
  });

  group('access control', () {
    Widget gated() => MaterialApp(
      home: AuthGate(
        authService: auth,
        userRecordService: records,
        boardService: board,
        authState: auth.authStateController.stream,
      ),
    );

    testWidgets('an incomplete profile cannot reach the board', (tester) async {
      board.initial = const [];
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

      await tester.pumpWidget(gated());
      auth.authStateController.add(FakeUser());
      await tester.pumpAndSettle();

      expect(find.byType(BoardScreen), findsNothing);
      expect(find.byType(CompleteProfileScreen), findsOneWidget);
    });

    testWidgets('a missing profile cannot reach the board', (tester) async {
      board.initial = const [];
      records.seed('test-uid', null);

      await tester.pumpWidget(gated());
      auth.authStateController.add(FakeUser());
      await tester.pumpAndSettle();

      expect(find.byType(BoardScreen), findsNothing);
      expect(find.byType(CompleteProfileScreen), findsOneWidget);
    });

    testWidgets('a complete profile reaches the board', (tester) async {
      board.initial = const [];
      records.seed('test-uid', completeRecord());

      await tester.pumpWidget(gated());
      auth.authStateController.add(FakeUser());
      await tester.pumpAndSettle();

      expect(find.byType(BoardScreen), findsOneWidget);
      expect(find.text('Signed in as Ada Lovelace'), findsOneWidget);
    });
  });


  group('ownership controls', () {
    testWidgets('Edit and Delete appear for the user\'s own messages', (
      tester,
    ) async {
      board.initial = [message(id: 'mine', authorUid: 'test-uid')];

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextButton, 'Edit'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Delete'), findsOneWidget);
    });

    testWidgets('neither control appears on another user\'s message', (
      tester,
    ) async {
      board.initial = [
        message(
          id: 'theirs',
          authorUid: 'someone-else',
          authorName: 'Grace Hopper',
          text: 'Not yours',
        ),
      ];

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      expect(find.text('Not yours'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Edit'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Delete'), findsNothing);
    });

    testWidgets('controls appear only on the owned message in a mixed list', (
      tester,
    ) async {
      board.initial = [
        message(id: 'mine', authorUid: 'test-uid', text: 'Mine'),
        message(id: 'theirs', authorUid: 'other', text: 'Theirs'),
      ];

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextButton, 'Edit'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Delete'), findsOneWidget);
    });

    testWidgets('an Edited indicator shows when editedAt is present', (
      tester,
    ) async {
      board.initial = [
        message(id: 'a', text: 'Plain'),
        message(
          id: 'b',
          text: 'Changed',
          editedAt: DateTime.utc(2026, 1, 3, 11, 0),
        ),
      ];

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      expect(find.text('Edited'), findsOneWidget);
    });
  });

  group('editing', () {
    Future<void> openEditDialog(WidgetTester tester) async {
      board.initial = [
        message(id: 'mine', authorUid: 'test-uid', text: 'Original text'),
      ];
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();
    }

    testWidgets('the dialog opens prefilled with the existing text', (
      tester,
    ) async {
      await openEditDialog(tester);

      expect(find.text('Edit Message'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.text, 'Original text');
    });

    testWidgets('Cancel closes the dialog without editing', (tester) async {
      await openEditDialog(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(board.editCalls, 0);
      expect(find.text('Original text'), findsOneWidget);
    });

    testWidgets('an emptied message is rejected without calling the service', (
      tester,
    ) async {
      await openEditDialog(tester);

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '   ',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(board.editCalls, 0);
      expect(find.text('A message cannot be empty.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('a valid edit calls editMessage once with the document ID', (
      tester,
    ) async {
      await openEditDialog(tester);

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Updated text',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(board.editCalls, 1);
      expect(board.lastEditedId, 'mine');
      expect(board.lastEditedText, 'Updated text');
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('the edited text arrives through the stream, not locally', (
      tester,
    ) async {
      await openEditDialog(tester);

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Updated text',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Firestore has not echoed yet, so the card still shows the old text.
      expect(find.text('Original text'), findsOneWidget);

      board.emit([
        message(
          id: 'mine',
          authorUid: 'test-uid',
          text: 'Updated text',
          editedAt: DateTime.utc(2026, 1, 4, 12, 0),
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Updated text'), findsOneWidget);
      expect(find.text('Original text'), findsNothing);
      expect(find.text('Edited'), findsOneWidget);
    });

    testWidgets('a failed edit keeps the dialog open with friendly feedback', (
      tester,
    ) async {
      board.editFailure = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      await openEditDialog(tester);

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Updated text',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text('You can only change your own messages.'),
        findsOneWidget,
      );
      expect(find.textContaining('permission-denied'), findsNothing);
      // The original message is untouched behind the dialog.
      expect(board.editCalls, 1);
    });

    testWidgets('a second Save tap while saving is ignored', (tester) async {
      board.pendingWrite = Completer<void>();
      await openEditDialog(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();

      expect(board.editCalls, 1);
      final save = tester.widget<FilledButton>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      expect(save.onPressed, isNull);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pump();
      expect(board.editCalls, 1);

      board.pendingWrite!.complete();
      await tester.pumpAndSettle();
    });
  });

  group('deleting', () {
    Future<void> openDeleteDialog(WidgetTester tester) async {
      board.initial = [
        message(id: 'mine', authorUid: 'test-uid', text: 'Delete me'),
      ];
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
    }

    testWidgets('deletion requires confirmation', (tester) async {
      await openDeleteDialog(tester);

      expect(find.text('Delete Message?'), findsOneWidget);
      expect(board.deleteCalls, 0, reason: 'nothing deleted before confirming');
    });

    testWidgets('cancelling deletion preserves the message', (tester) async {
      await openDeleteDialog(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(board.deleteCalls, 0);
      expect(find.text('Delete me'), findsOneWidget);
    });

    testWidgets('confirmed deletion targets exactly one document ID', (
      tester,
    ) async {
      await openDeleteDialog(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Delete'),
        ),
      );
      await tester.pumpAndSettle();

      expect(board.deleteCalls, 1);
      expect(board.deletedIds, ['mine']);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('deleting one of three messages leaves the other two', (
      tester,
    ) async {
      board.initial = [
        message(id: 'first', authorUid: 'test-uid', text: 'First'),
        message(id: 'second', authorUid: 'test-uid', text: 'Second'),
        message(id: 'third', authorUid: 'test-uid', text: 'Third'),
      ];

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      // Tap Delete on the middle card only.
      await tester.tap(find.widgetWithText(TextButton, 'Delete').at(1));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Delete'),
        ),
      );
      await tester.pumpAndSettle();

      expect(board.deletedIds, ['second']);

      board.emit([
        message(id: 'first', authorUid: 'test-uid', text: 'First'),
        message(id: 'third', authorUid: 'test-uid', text: 'Third'),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('First'), findsOneWidget);
      expect(find.text('Third'), findsOneWidget);
      expect(find.text('Second'), findsNothing);
    });

    testWidgets('a failed deletion shows friendly feedback and keeps it', (
      tester,
    ) async {
      board.deleteFailure = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      await openDeleteDialog(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Delete'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text('You can only change your own messages.'),
        findsOneWidget,
      );
      expect(find.textContaining('permission-denied'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Delete me'), findsOneWidget);
    });

    testWidgets('a missing document reports a safe message', (tester) async {
      board.deleteFailure = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'not-found',
      );
      await openDeleteDialog(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Delete'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('That message no longer exists.'), findsOneWidget);
    });

    testWidgets('a second Delete tap while deleting is ignored', (
      tester,
    ) async {
      board.pendingWrite = Completer<void>();
      await openDeleteDialog(tester);

      final confirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Delete'),
      );
      await tester.tap(confirm);
      await tester.pump();

      expect(board.deleteCalls, 1);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pump();
      expect(board.deleteCalls, 1);

      board.pendingWrite!.complete();
      await tester.pumpAndSettle();
    });
  });

  group('formatMessageTime', () {
    test('reports a pending write', () {
      expect(formatMessageTime(null), 'Sending…');
    });

    test('formats a known time', () {
      final formatted = formatMessageTime(DateTime(2026, 3, 4, 14, 5));
      expect(formatted, '03/04/2026 14:05');
    });
  });
}
