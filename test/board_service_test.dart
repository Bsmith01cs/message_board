import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_board/models/board_message.dart';
import 'package:message_board/services/board_service.dart';

import 'fake_firestore.dart';
import 'fakes.dart';

void main() {
  late FakeFirestore firestore;
  late FakeCollection messages;
  late FakeAuthService auth;
  late BoardService board;

  setUp(() {
    firestore = FakeFirestore();
    messages = firestore.collectionNamed(messagesCollection);
    auth = FakeAuthService()..signedInUser = FakeUser(uid: 'uid-1');
    board = BoardService(firestore: firestore, authService: auth);
  });
  tearDown(() {
    messages.dispose();
    auth.authStateController.close();
  });

  group('postMessage', () {
    test('writes the message with the authenticated author uid', () async {
      await board.postMessage(text: '  Hello board  ', authorName: 'Ada L');

      expect(messages.adds, hasLength(1));
      final write = messages.adds.single;
      expect(write.keys.toSet(), messageFields.toSet());
      expect(write['text'], 'Hello board');
      expect(write['authorUid'], 'uid-1');
      expect(write['authorName'], 'Ada L');
      expect(write['editedAt'], isNull);
    });

    test('uses a server timestamp for createdAt', () async {
      await board.postMessage(text: 'Hello', authorName: 'Ada L');

      expect(messages.adds.single['createdAt'], FieldValue.serverTimestamp());
    });

    test('ignores any caller-supplied author uid in favour of Auth', () async {
      auth.signedInUser = FakeUser(uid: 'real-uid');

      await board.postMessage(text: 'Hello', authorName: 'uid-999');

      // authorName is display text only; the uid always comes from Auth.
      expect(messages.adds.single['authorUid'], 'real-uid');
    });

    test('rejects empty and whitespace-only text without writing', () async {
      await expectLater(
        board.postMessage(text: '   ', authorName: 'Ada L'),
        throwsA(isA<BoardServiceException>()),
      );
      await expectLater(
        board.postMessage(text: '', authorName: 'Ada L'),
        throwsA(isA<BoardServiceException>()),
      );

      expect(messages.adds, isEmpty);
    });

    test('an unauthenticated user cannot post', () async {
      auth.signedInUser = null;

      await expectLater(
        board.postMessage(text: 'Hello', authorName: 'Ada L'),
        throwsA(isA<BoardServiceException>()),
      );
      expect(messages.adds, isEmpty);
    });
  });

  group('editMessage', () {
    setUp(() {
      messages.seed('msg1', {
        'text': 'Original',
        'authorUid': 'uid-1',
        'authorName': 'Ada L',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'editedAt': null,
      });
    });

    test('updates only text and editedAt', () async {
      await board.editMessage(messageId: 'msg1', text: ' Updated ');

      final update = messages.updates['msg1']!;
      expect(update.keys.toSet(), {'text', 'editedAt'});
      expect(update['text'], 'Updated');
      expect(update['editedAt'], FieldValue.serverTimestamp());
    });

    test('leaves authorUid and createdAt untouched', () async {
      await board.editMessage(messageId: 'msg1', text: 'Updated');

      final stored = messages.documents['msg1']!;
      expect(stored['authorUid'], 'uid-1');
      expect(stored['createdAt'], Timestamp.fromDate(DateTime.utc(2026, 1, 1)));
      expect(stored['text'], 'Updated');
      expect(stored['editedAt'], isA<Timestamp>());
    });

    test('rejects empty replacement text', () async {
      await expectLater(
        board.editMessage(messageId: 'msg1', text: '  '),
        throwsA(isA<BoardServiceException>()),
      );
      expect(messages.updates, isEmpty);
    });

    test('an unauthenticated user cannot edit', () async {
      auth.signedInUser = null;

      await expectLater(
        board.editMessage(messageId: 'msg1', text: 'Updated'),
        throwsA(isA<BoardServiceException>()),
      );
      expect(messages.updates, isEmpty);
    });
  });

  group('deleteMessage', () {
    test('deletes exactly the one requested document', () async {
      messages.seed('msg1', {'text': 'One'});
      messages.seed('msg2', {'text': 'Two'});

      await board.deleteMessage('msg1');

      expect(messages.deletedIds, ['msg1']);
      expect(messages.documents.keys, ['msg2']);
    });

    test('an unauthenticated user cannot delete', () async {
      messages.seed('msg1', {'text': 'One'});
      auth.signedInUser = null;

      await expectLater(
        board.deleteMessage('msg1'),
        throwsA(isA<BoardServiceException>()),
      );
      expect(messages.deletedIds, isEmpty);
      expect(messages.documents.containsKey('msg1'), isTrue);
    });
  });

  group('messageBoard', () {
    test('streams messages ordered by createdAt, oldest first', () async {
      messages.seed('newer', {
        'text': 'Second',
        'authorUid': 'uid-1',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 2)),
      });
      messages.seed('older', {
        'text': 'First',
        'authorUid': 'uid-1',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      });

      final board0 = await board.messageBoard().first;

      expect(messages.orderByField, 'createdAt');
      expect(messages.orderByDescending, isFalse);
      expect(board0.map((m) => m.text), ['First', 'Second']);
      expect(board0.map((m) => m.id), ['older', 'newer']);
      expect(board0.first, isA<BoardMessage>());
    });

    test('the stream updates when a message is posted', () async {
      final updates = <List<BoardMessage>>[];
      final subscription = board.messageBoard().listen(updates.add);
      await Future<void>.delayed(Duration.zero);

      expect(updates.last, isEmpty);

      await board.postMessage(text: 'Live update', authorName: 'Ada L');
      await Future<void>.delayed(Duration.zero);

      expect(updates.last.map((m) => m.text), ['Live update']);
      await subscription.cancel();
    });
  });
}
