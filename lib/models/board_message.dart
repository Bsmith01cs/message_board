import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/user_record_service.dart';

/// Firestore collection holding one document per board message.
const messagesCollection = 'messages';

/// The fields a message document may contain. Nothing else is written.
const messageFields = <String>[
  'text',
  'authorUid',
  'authorName',
  'createdAt',
  'editedAt',
];

/// A message document read back from Firestore.
class BoardMessage {
  const BoardMessage({
    required this.id,
    required this.text,
    required this.authorUid,
    required this.authorName,
    required this.createdAt,
    this.editedAt,
  });

  /// The Firestore document ID, needed for edit and delete.
  final String id;

  final String text;
  final String authorUid;
  final String authorName;

  /// Null only while a server timestamp write is still pending locally.
  final DateTime? createdAt;

  /// Null when the message has never been edited.
  final DateTime? editedAt;

  bool get isEdited => editedAt != null;

  /// Ownership check for the UI. Security rules remain the real authority.
  bool isOwnedBy(String? uid) => uid != null && uid == authorUid;

  /// Tolerates missing or wrongly typed fields so one bad document cannot
  /// break the whole board.
  static BoardMessage fromMap(String id, Map<String, dynamic>? data) {
    final fields = data ?? const <String, dynamic>{};
    final createdAt = fields['createdAt'];
    final editedAt = fields['editedAt'];
    return BoardMessage(
      id: id,
      text: (fields['text'] as String?) ?? '',
      authorUid: (fields['authorUid'] as String?) ?? '',
      authorName: (fields['authorName'] as String?) ?? '',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : null,
      editedAt: editedAt is Timestamp ? editedAt.toDate() : null,
    );
  }
}

/// The display name stored on a message, built from the user's profile.
String authorNameFrom(UserRecord record) =>
    '${record.firstName} ${record.lastName}'.trim();

/// True when [text] has content once surrounding whitespace is removed.
bool isValidMessageText(String? text) => (text ?? '').trim().isNotEmpty;

/// Builds a new message document. Exposed so the field set and the server
/// timestamp can be verified without touching Firestore.
Map<String, Object?> buildNewMessage({
  required String text,
  required String authorUid,
  required String authorName,
}) {
  return <String, Object?>{
    'text': text.trim(),
    'authorUid': authorUid,
    'authorName': authorName,
    'createdAt': FieldValue.serverTimestamp(),
    'editedAt': null,
  };
}

/// Builds the update applied when a message is edited. Deliberately contains
/// only `text` and `editedAt`, so ownership and creation time cannot change.
Map<String, Object?> buildMessageEdit({required String text}) {
  return <String, Object?>{
    'text': text.trim(),
    'editedAt': FieldValue.serverTimestamp(),
  };
}
