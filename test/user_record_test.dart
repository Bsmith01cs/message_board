import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_board/services/user_record_service.dart';

void main() {
  group('buildNewUserRecord', () {
    test('writes exactly the five required fields', () {
      final record = buildNewUserRecord(
        uid: 'abc123',
        firstName: 'Ada',
        lastName: 'Lovelace',
      );

      expect(record.keys.toSet(), requiredUserFields.toSet());
    });

    test('uses the Auth uid as the stored uid', () {
      final record = buildNewUserRecord(
        uid: 'abc123',
        firstName: 'Ada',
        lastName: 'Lovelace',
      );

      expect(record['uid'], 'abc123');
    });

    test('registrationDateTime is a server timestamp', () {
      final record = buildNewUserRecord(
        uid: 'abc123',
        firstName: 'Ada',
        lastName: 'Lovelace',
      );

      expect(record['registrationDateTime'], isA<FieldValue>());
      expect(record['registrationDateTime'], FieldValue.serverTimestamp());
    });

    test('role defaults to member and names are trimmed', () {
      final record = buildNewUserRecord(
        uid: 'abc123',
        firstName: '  Ada ',
        lastName: ' Lovelace  ',
      );

      expect(record['role'], 'member');
      expect(record['firstName'], 'Ada');
      expect(record['lastName'], 'Lovelace');
    });
  });

  group('UserRecord.isComplete', () {
    UserRecord build({
      String uid = 'abc123',
      String firstName = 'Ada',
      String lastName = 'Lovelace',
      String role = 'member',
      DateTime? registeredAt,
      bool pending = false,
    }) => UserRecord(
      uid: uid,
      firstName: firstName,
      lastName: lastName,
      role: role,
      registrationDateTime: registeredAt ?? DateTime(2026),
      timestampPending: pending,
    );

    test('a full record is complete', () {
      expect(build().isComplete, isTrue);
    });

    test('a missing name makes it incomplete', () {
      expect(build(firstName: '').isComplete, isFalse);
      expect(build(lastName: '  ').isComplete, isFalse);
    });

    test('a missing role or uid makes it incomplete', () {
      expect(build(role: '').isComplete, isFalse);
      expect(build(uid: '').isComplete, isFalse);
    });

    test('a pending server timestamp still counts as complete', () {
      final record = UserRecord(
        uid: 'abc123',
        firstName: 'Ada',
        lastName: 'Lovelace',
        role: 'member',
        registrationDateTime: null,
        timestampPending: true,
      );

      expect(record.isComplete, isTrue);
    });

    test('no timestamp and no pending write is incomplete', () {
      final record = UserRecord(
        uid: 'abc123',
        firstName: 'Ada',
        lastName: 'Lovelace',
        role: 'member',
        registrationDateTime: null,
      );

      expect(record.isComplete, isFalse);
    });
  });

  group('fromMap', () {
    test('trims strings and converts the Firestore timestamp', () {
      final record = UserRecord.fromMap({
        'uid': 'abc123',
        'firstName': ' Ada ',
        'lastName': 'Lovelace',
        'role': 'member',
        'registrationDateTime': Timestamp.fromDate(DateTime.utc(2026, 1, 2)),
      });

      expect(record.firstName, 'Ada');
      expect(record.registrationDateTime, DateTime.utc(2026, 1, 2).toLocal());
      expect(record.isComplete, isTrue);
    });

    test('a partial document is reported incomplete, not crashed on', () {
      final record = UserRecord.fromMap({'uid': 'abc123'});

      expect(record.firstName, '');
      expect(record.isComplete, isFalse);
    });
  });

  group('friendlyFirestoreError', () {
    test('permission-denied has its own message', () {
      final message = friendlyFirestoreError(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );

      expect(message, contains('permission'));
      expect(message, isNot(contains('permission-denied')));
    });

    test('other failures fall back to a generic message', () {
      final message = friendlyFirestoreError(
        FirebaseException(plugin: 'cloud_firestore', code: 'aborted'),
      );

      expect(message, 'Something went wrong. Please try again.');
    });
  });
}
