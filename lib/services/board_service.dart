import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/board_message.dart';
import 'auth_service.dart';

/// Thrown for problems the UI should explain to the user.
class BoardServiceException implements Exception {
  const BoardServiceException(this.message);

  final String message;

  @override
  String toString() => 'BoardServiceException: $message';
}

/// All Firestore reads and writes for `messages/{msgId}` live here.
class BoardService {
  BoardService({FirebaseFirestore? firestore, AuthService? authService})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _authService = authService ?? AuthService();

  final FirebaseFirestore _firestore;
  final AuthService _authService;

  CollectionReference<Map<String, dynamic>> get _messages =>
      _firestore.collection(messagesCollection);

  /// Realtime stream of the board, oldest message first.
  Stream<List<BoardMessage>> messageBoard() {
    return _messages.orderBy('createdAt').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => BoardMessage.fromMap(doc.id, doc.data()))
          .toList();
    });
  }

  /// Creates a message owned by the currently authenticated user.
  /// The author UID always comes from Firebase Auth, never from the caller.
  Future<void> postMessage({
    required String text,
    required String authorName,
  }) async {
    if (!isValidMessageText(text)) {
      throw const BoardServiceException('Enter a message before posting.');
    }

    final uid = _authService.currentUser?.uid;
    if (uid == null) {
      throw const BoardServiceException('You must be signed in to post.');
    }

    await _messages.add(
      buildNewMessage(text: text, authorUid: uid, authorName: authorName),
    );
  }

  /// Updates the text of one message. Only `text` and `editedAt` are written,
  /// so `authorUid` and `createdAt` cannot be altered here.
  Future<void> editMessage({
    required String messageId,
    required String text,
  }) async {
    if (!isValidMessageText(text)) {
      throw const BoardServiceException('A message cannot be empty.');
    }
    if (_authService.currentUser == null) {
      throw const BoardServiceException('You must be signed in to edit.');
    }

    await _messages.doc(messageId).update(buildMessageEdit(text: text));
  }

  /// Deletes exactly the one message identified by [messageId].
  Future<void> deleteMessage(String messageId) async {
    if (_authService.currentUser == null) {
      throw const BoardServiceException('You must be signed in to delete.');
    }

    await _messages.doc(messageId).delete();
  }
}

/// Turns a board failure into a message that is safe to show.
String friendlyBoardError(Object error) {
  if (error is BoardServiceException) return error.message;
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'You can only change your own messages.';
      case 'not-found':
        return 'That message no longer exists.';
      case 'unavailable':
      case 'network-request-failed':
        return 'No internet connection. Please try again.';
    }
  }
  return 'Something went wrong. Please try again.';
}
