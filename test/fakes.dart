import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_board/models/board_message.dart';
import 'package:message_board/services/auth_service.dart';
import 'package:message_board/services/board_service.dart';
import 'package:message_board/services/user_record_service.dart';

/// Stands in for a Firebase [User] so tests need no live Firebase.
class FakeUser extends Fake implements User {
  FakeUser({this.uid = 'test-uid'});

  @override
  final String uid;

  @override
  String? get email => 'student@example.com';
}

class FakeUserCredential extends Fake implements UserCredential {
  FakeUserCredential([this.user]);

  @override
  final User? user;
}

/// In-memory stand-in for Firestore `users/{uid}`.
UserRecord completeRecord({
  String uid = 'test-uid',
  String firstName = 'Ada',
  String lastName = 'Lovelace',
  String role = defaultUserRole,
}) => UserRecord(
  uid: uid,
  firstName: firstName,
  lastName: lastName,
  role: role,
  registrationDateTime: DateTime(2026, 1, 1),
);

class FakeUserRecordService extends Fake implements UserRecordService {
  final controllers = <String, StreamController<UserRecord?>>{};

  /// First value each watched uid receives, replayed on subscribe.
  final initial = <String, UserRecord?>{};

  /// Documents keyed by uid, mirroring what saveProfile would store.
  final documents = <String, Map<String, Object?>>{};

  int saveCalls = 0;
  Map<String, Object?>? lastWrite;
  String? lastWriteUid;

  /// Thrown by [saveProfile] when set.
  Object? saveFailure;

  /// Pushed as a stream error by [watch] when set.
  Object? watchFailure;

  StreamController<UserRecord?> controllerFor(String uid) =>
      controllers.putIfAbsent(
        uid,
        () => StreamController<UserRecord?>.broadcast(),
      );

  void emit(String uid, UserRecord? record) => controllerFor(uid).add(record);

  void seed(String uid, UserRecord? record) => initial[uid] = record;

  @override
  Stream<UserRecord?> watch(String uid) async* {
    if (watchFailure != null) throw watchFailure!;
    if (initial.containsKey(uid)) yield initial[uid];
    yield* controllerFor(uid).stream;
  }

  @override
  Future<UserRecord?> fetch(String uid) async {
    final data = documents[uid];
    return data == null ? null : UserRecord.fromMap(data.cast<String, dynamic>());
  }

  @override
  Future<void> saveProfile({
    required String uid,
    required String firstName,
    required String lastName,
  }) async {
    saveCalls++;
    if (saveFailure != null) throw saveFailure!;

    final existing = documents[uid];
    if (existing != null) {
      final record = UserRecord.fromMap(existing.cast<String, dynamic>());
      // Mirrors the real service: a complete profile is never overwritten.
      if (record.isComplete) return;
    }

    final write = buildNewUserRecord(
      uid: uid,
      firstName: firstName,
      lastName: lastName,
      role: (existing?['role'] as String?) ?? defaultUserRole,
    );
    if (existing?['registrationDateTime'] != null) {
      write['registrationDateTime'] = existing!['registrationDateTime'];
    }
    lastWriteUid = uid;
    lastWrite = write;
    documents[uid] = {...?existing, ...write};
  }

  void disposeControllers() {
    for (final controller in controllers.values) {
      controller.close();
    }
  }
}

/// Records calls and lets each test control when the call completes.
class FakeAuthService extends Fake implements AuthService {
  final authStateController = StreamController<User?>.broadcast();

  int signInCalls = 0;
  int registerCalls = 0;
  int signOutCalls = 0;
  String? lastEmail;

  /// Set to pause a call so the loading state can be inspected.
  Completer<UserCredential>? pending;

  /// Thrown by [signIn] and [register] when set.
  Object? failure;

  /// The user BoardService and friends see as signed in; null means signed out.
  User? signedInUser;

  @override
  User? get currentUser => signedInUser;

  @override
  Stream<User?> authStateChanges() => authStateController.stream;

  Future<UserCredential> _respond(String email) {
    lastEmail = email.trim();
    if (pending != null) return pending!.future;
    if (failure != null) return Future.error(failure!);
    return Future.value(FakeUserCredential(FakeUser()));
  }

  @override
  Future<UserCredential> signIn(String email, String password) {
    signInCalls++;
    return _respond(email);
  }

  @override
  Future<UserCredential> register(String email, String password) {
    registerCalls++;
    return _respond(email);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}


/// In-memory stand-in for BoardService. Nothing here touches Firestore.
class FakeBoardService extends Fake implements BoardService {
  final controller = StreamController<List<BoardMessage>>.broadcast();

  int postCalls = 0;
  int editCalls = 0;
  int deleteCalls = 0;
  String? lastText;
  String? lastAuthorName;
  String? lastEditedId;
  String? lastEditedText;
  final deletedIds = <String>[];

  /// Set to pause a post so the loading state can be inspected.
  Completer<void>? pending;

  /// Set to pause an edit or delete so the loading state can be inspected.
  Completer<void>? pendingWrite;

  /// Thrown by [postMessage] when set.
  Object? postFailure;

  /// Thrown by [editMessage] when set.
  Object? editFailure;

  /// Thrown by [deleteMessage] when set.
  Object? deleteFailure;

  /// Pushed as a stream error by [messageBoard] when set.
  Object? streamFailure;

  /// First value the board stream emits, replayed on subscribe.
  List<BoardMessage>? initial;

  void emit(List<BoardMessage> messages) => controller.add(messages);

  @override
  Stream<List<BoardMessage>> messageBoard() async* {
    if (streamFailure != null) throw streamFailure!;
    if (initial != null) yield initial!;
    yield* controller.stream;
  }

  @override
  Future<void> postMessage({
    required String text,
    required String authorName,
  }) async {
    postCalls++;
    lastText = text;
    lastAuthorName = authorName;
    if (pending != null) return pending!.future;
    if (postFailure != null) throw postFailure!;
  }

  @override
  Future<void> editMessage({
    required String messageId,
    required String text,
  }) async {
    editCalls++;
    lastEditedId = messageId;
    lastEditedText = text;
    if (pendingWrite != null) return pendingWrite!.future;
    if (editFailure != null) throw editFailure!;
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    deleteCalls++;
    deletedIds.add(messageId);
    if (pendingWrite != null) return pendingWrite!.future;
    if (deleteFailure != null) throw deleteFailure!;
  }

  void dispose() => controller.close();
}

BoardMessage message({
  String id = 'msg1',
  String text = 'Hello board',
  String authorUid = 'test-uid',
  String authorName = 'Ada Lovelace',
  DateTime? createdAt,
  DateTime? editedAt,
  /// True to model a server timestamp that has not been confirmed yet.
  bool pendingCreatedAt = false,
}) => BoardMessage(
  id: id,
  text: text,
  authorUid: authorUid,
  authorName: authorName,
  createdAt: pendingCreatedAt
      ? null
      : (createdAt ?? DateTime.utc(2026, 1, 1, 9, 30)),
  editedAt: editedAt,
);
