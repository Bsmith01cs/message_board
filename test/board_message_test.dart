import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_board/models/board_message.dart';
import 'package:message_board/services/user_record_service.dart';

void main() {
  group('BoardMessage.fromMap', () {
    test('maps every field and keeps the document ID', () {
      final message = BoardMessage.fromMap('msg1', {
        'text': 'Hello board',
        'authorUid': 'uid-1',
        'authorName': 'Ada Lovelace',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'editedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 2)),
      });

      expect(message.id, 'msg1');
      expect(message.text, 'Hello board');
      expect(message.authorUid, 'uid-1');
      expect(message.authorName, 'Ada Lovelace');
      expect(message.createdAt, DateTime.utc(2026, 1, 1).toLocal());
      expect(message.editedAt, DateTime.utc(2026, 1, 2).toLocal());
      expect(message.isEdited, isTrue);
    });

    test('an absent editedAt leaves the message unedited', () {
      final message = BoardMessage.fromMap('msg2', {
        'text': 'First post',
        'authorUid': 'uid-1',
        'authorName': 'Ada Lovelace',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      });

      expect(message.editedAt, isNull);
      expect(message.isEdited, isFalse);
    });

    test('an explicitly null editedAt is handled', () {
      final message = BoardMessage.fromMap('msg3', {
        'text': 'Post',
        'editedAt': null,
      });

      expect(message.editedAt, isNull);
      expect(message.isEdited, isFalse);
    });

    test('a pending createdAt timestamp reads as null, not a crash', () {
      final message = BoardMessage.fromMap('msg4', {'text': 'Post'});

      expect(message.createdAt, isNull);
      expect(message.authorUid, '');
    });

    test('a null document does not throw', () {
      final message = BoardMessage.fromMap('msg5', null);

      expect(message.text, '');
      expect(message.id, 'msg5');
    });
  });

  group('ownership', () {
    final message = BoardMessage.fromMap('msg1', {
      'text': 'Post',
      'authorUid': 'uid-1',
    });

    test('matches the author uid only', () {
      expect(message.isOwnedBy('uid-1'), isTrue);
      expect(message.isOwnedBy('uid-2'), isFalse);
      expect(message.isOwnedBy(null), isFalse);
    });
  });

  group('isValidMessageText', () {
    test('rejects empty and whitespace-only text', () {
      expect(isValidMessageText(null), isFalse);
      expect(isValidMessageText(''), isFalse);
      expect(isValidMessageText('   '), isFalse);
      expect(isValidMessageText('\n\t '), isFalse);
    });

    test('accepts real content', () {
      expect(isValidMessageText('hi'), isTrue);
      expect(isValidMessageText('  hi  '), isTrue);
    });
  });

  group('authorNameFrom', () {
    test('joins the profile first and last name', () {
      final record = UserRecord(
        uid: 'uid-1',
        firstName: 'Ada',
        lastName: 'Lovelace',
        role: defaultUserRole,
        registrationDateTime: DateTime(2026),
      );

      expect(authorNameFrom(record), 'Ada Lovelace');
    });
  });

  group('buildNewMessage', () {
    test('writes the five message fields and nothing else', () {
      final data = buildNewMessage(
        text: '  Hello  ',
        authorUid: 'uid-1',
        authorName: 'Ada Lovelace',
      );

      expect(data.keys.toSet(), messageFields.toSet());
      expect(data['text'], 'Hello');
      expect(data['authorUid'], 'uid-1');
      expect(data['createdAt'], FieldValue.serverTimestamp());
      expect(data['editedAt'], isNull);
    });
  });

  group('buildMessageEdit', () {
    test('changes only text and editedAt', () {
      final data = buildMessageEdit(text: ' Updated ');

      expect(data.keys.toSet(), {'text', 'editedAt'});
      expect(data.containsKey('authorUid'), isFalse);
      expect(data.containsKey('authorName'), isFalse);
      expect(data.containsKey('createdAt'), isFalse);
      expect(data['text'], 'Updated');
      expect(data['editedAt'], FieldValue.serverTimestamp());
    });
  });
}
