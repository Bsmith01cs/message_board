// Firestore's reference and snapshot types are sealed and immutable, so a
// hand-written test double has to opt out of those two lints. Test-only file.
// ignore_for_file: subtype_of_sealed_class, must_be_immutable

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// A very small in-memory stand-in for the parts of Firestore that
/// BoardService uses: collection(), add(), doc().update(), doc().delete()
/// and orderBy().snapshots(). Nothing here talks to a real Firebase project.
class FakeFirestore extends Fake implements FirebaseFirestore {
  final collections = <String, FakeCollection>{};

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      collectionNamed(path);

  FakeCollection collectionNamed(String path) =>
      collections.putIfAbsent(path, () => FakeCollection());
}

class FakeCollection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  /// Stored documents, with server timestamps already resolved the way the
  /// real backend would resolve them.
  final documents = <String, Map<String, Object?>>{};

  /// Raw writes exactly as BoardService passed them, so a test can assert
  /// that FieldValue.serverTimestamp() was used.
  final adds = <Map<String, Object?>>[];
  final updates = <String, Map<String, Object?>>{};
  final deletedIds = <String>[];

  String? orderByField;
  bool orderByDescending = false;

  final _changes = StreamController<void>.broadcast();
  int _autoId = 0;
  int _clock = 0;

  void dispose() => _changes.close();

  /// Puts a document in place without going through BoardService.
  void seed(String id, Map<String, Object?> data) {
    documents[id] = {...data};
    _notify();
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Mimics the backend filling in a server timestamp on write.
  Map<String, Object?> _resolve(Map<String, Object?> data) {
    final resolved = <String, Object?>{};
    data.forEach((key, value) {
      if (value == FieldValue.serverTimestamp()) {
        resolved[key] = Timestamp.fromMillisecondsSinceEpoch(
          1700000000000 + (++_clock) * 1000,
        );
      } else {
        resolved[key] = value;
      }
    });
    return resolved;
  }

  @override
  Future<DocumentReference<Map<String, dynamic>>> add(
    Map<String, dynamic> data,
  ) async {
    adds.add({...data});
    final id = 'msg${++_autoId}';
    documents[id] = _resolve(data);
    _notify();
    return FakeDocumentReference(this, id);
  }

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      FakeDocumentReference(this, path!);

  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) {
    orderByField = field as String;
    orderByDescending = descending;
    return FakeQuery(this);
  }

  List<String> get orderedIds {
    final ids = documents.keys.toList();
    final field = orderByField ?? 'createdAt';
    ids.sort((a, b) {
      final left = documents[a]![field];
      final right = documents[b]![field];
      if (left is! Timestamp) return 1;
      if (right is! Timestamp) return -1;
      return left.compareTo(right);
    });
    return orderByDescending ? ids.reversed.toList() : ids;
  }
}

class FakeDocumentReference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  FakeDocumentReference(this._collection, this.id);

  final FakeCollection _collection;

  @override
  final String id;

  @override
  Future<void> update(Map<Object, Object?> data) async {
    if (!_collection.documents.containsKey(id)) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'not-found');
    }
    _collection.updates[id] = data.cast<String, Object?>();
    _collection.documents[id] = {
      ..._collection.documents[id]!,
      ..._collection._resolve(data.cast<String, Object?>()),
    };
    _collection._notify();
  }

  @override
  Future<void> delete() async {
    _collection.deletedIds.add(id);
    _collection.documents.remove(id);
    _collection._notify();
  }
}

class FakeQuery extends Fake implements Query<Map<String, dynamic>> {
  FakeQuery(this._collection);

  final FakeCollection _collection;

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) async* {
    yield _snapshot();
    yield* _collection._changes.stream.map((_) => _snapshot());
  }

  FakeQuerySnapshot _snapshot() => FakeQuerySnapshot(
    _collection.orderedIds
        .map(
          (id) => FakeQueryDocumentSnapshot(id, _collection.documents[id]!)
              as QueryDocumentSnapshot<Map<String, dynamic>>,
        )
        .toList(),
  );
}

class FakeQuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  FakeQuerySnapshot(this.docs);

  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
}

class FakeQueryDocumentSnapshot extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  FakeQueryDocumentSnapshot(this.id, this._data);

  final Map<String, Object?> _data;

  @override
  final String id;

  @override
  Map<String, dynamic> data() => _data.cast<String, dynamic>();
}
