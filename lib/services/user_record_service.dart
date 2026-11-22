import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore collection holding one document per registered user.
const usersCollection = 'users';

/// The five fields every user document must contain.
const requiredUserFields = <String>[
  'uid',
  'firstName',
  'lastName',
  'role',
  'registrationDateTime',
];

/// Descriptive default only. The role in this document never grants
/// privileges; access is decided by Firebase Auth and security rules.
const defaultUserRole = 'member';

/// A user document read back from Firestore.
class UserRecord {
  const UserRecord({
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.registrationDateTime,
    this.timestampPending = false,
  });

  final String uid;
  final String firstName;
  final String lastName;
  final String role;
  final DateTime? registrationDateTime;

  /// True while a server timestamp written locally has not been confirmed.
  final bool timestampPending;

  /// All five required fields are present and usable.
  bool get isComplete =>
      uid.trim().isNotEmpty &&
      firstName.trim().isNotEmpty &&
      lastName.trim().isNotEmpty &&
      role.trim().isNotEmpty &&
      (registrationDateTime != null || timestampPending);

  static UserRecord fromMap(
    Map<String, dynamic> data, {
    bool timestampPending = false,
  }) {
    final timestamp = data['registrationDateTime'];
    return UserRecord(
      uid: (data['uid'] as String?)?.trim() ?? '',
      firstName: (data['firstName'] as String?)?.trim() ?? '',
      lastName: (data['lastName'] as String?)?.trim() ?? '',
      role: (data['role'] as String?)?.trim() ?? '',
      registrationDateTime: timestamp is Timestamp ? timestamp.toDate() : null,
      timestampPending: timestampPending,
    );
  }
}

/// Builds the document written for a brand new user. Exposed so the field set
/// and the server timestamp can be verified without touching Firestore.
Map<String, Object?> buildNewUserRecord({
  required String uid,
  required String firstName,
  required String lastName,
  String role = defaultUserRole,
}) {
  return <String, Object?>{
    'uid': uid,
    'firstName': firstName.trim(),
    'lastName': lastName.trim(),
    'role': role,
    'registrationDateTime': FieldValue.serverTimestamp(),
  };
}

/// All Firestore reads and writes for `users/{uid}` live here.
class UserRecordService {
  UserRecordService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _firestore.collection(usersCollection).doc(uid);

  /// Emits the user's record, or null when the document does not exist.
  /// Permission failures surface as a stream error, never as a null record.
  Stream<UserRecord?> watch(String uid) {
    return _doc(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return null;
      return UserRecord.fromMap(
        data,
        timestampPending: snapshot.metadata.hasPendingWrites,
      );
    });
  }

  /// One-off read. Returns null when the document does not exist.
  Future<UserRecord?> fetch(String uid) async {
    final snapshot = await _doc(uid).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return UserRecord.fromMap(data);
  }

  /// Writes the record for [uid] only when something is actually missing.
  /// An existing complete profile is left untouched, and an existing
  /// registration time and role are always preserved.
  Future<void> saveProfile({
    required String uid,
    required String firstName,
    required String lastName,
  }) async {
    final doc = _doc(uid);
    final snapshot = await doc.get();
    final data = snapshot.data();

    if (data != null) {
      final existing = UserRecord.fromMap(data);
      if (existing.isComplete) return;
    }

    final update = <String, Object?>{
      'uid': uid,
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'role': (data?['role'] as String?)?.trim().isNotEmpty == true
          ? data!['role']
          : defaultUserRole,
    };
    // Never reset an original registration time that is already stored.
    if (data == null || data['registrationDateTime'] == null) {
      update['registrationDateTime'] = FieldValue.serverTimestamp();
    }

    await doc.set(update, SetOptions(merge: true));
  }
}

/// Turns a Firestore failure into a message that is safe to show.
/// Permission problems are reported separately from everything else.
String friendlyFirestoreError(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'You do not have permission to access your profile. '
            'Please contact your instructor.';
      case 'unavailable':
      case 'network-request-failed':
        return 'No internet connection. Please try again.';
      case 'not-found':
        return 'Your profile could not be found.';
    }
  }
  return 'Something went wrong. Please try again.';
}
