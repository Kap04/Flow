import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_app/sprint_persistence.dart';

// Minimal fake Firestore implementation sufficient for the helper
class _FakeCollection {
  final List<Map<String, dynamic>> docs = [];
  Future<void> add(Map<String, dynamic> data) async {
    docs.add(Map<String, dynamic>.from(data));
  }
}

class _FakeDoc {
  final Map<String, _FakeCollection> _collections = {};
  _FakeCollection collection(String name) => _collections.putIfAbsent(name, () => _FakeCollection());
}

class _FakeFirestore {
  final Map<String, _FakeCollection> _top = {};
  _FakeDoc doc(String id) {
    // For our usage we need users -> doc(userId) -> collection('sprint_sessions')
    return _FakeDoc();
  }

  _FakeCollection collection(String name) => _top.putIfAbsent(name, () => _FakeCollection());
}

void main() {
  test('saveSprintSessionRecord writes actualMinutes to fake firestore', () async {
    final fake = _FakeFirestore();
    final userId = 'test-user-1';

    // For our fake, implement collection('users').doc(userId).collection('sprint_sessions').add
    // We'll create a small wrapper to match that chain.
    final users = fake.collection('users');
    // simulate doc(userId)
    final userDoc = _FakeDoc();
    final sprintCol = userDoc.collection('sprint_sessions');

    // Monkey-patch by placing the user's sprint collection into top-level map under a special key
    // (This is a lightweight shim specifically for the test)
  fake._top['__users/${userId}/sprint_sessions'] = sprintCol;

    // Create data
    final data = {
      'goalName': 'Test Goal',
      'sprintName': 'Sprint 1',
      'sprintIndex': 0,
      'plannedMinutes': 25,
      'actualMinutes': 12,
      'completed': true,
      'aborted': false,
    };

    // The helper will call: firestore.collection('users').doc(userId).collection('sprint_sessions').add(data)
    // Our fake can't exactly mirror that chain, so we provide a small shim object that implements the used API.
    final shim = _ShimFirestoreForTest(fake, userId);

    await saveSprintSessionRecord(userId: userId, data: data, firestore: shim);

  final savedList = fake._top['__users/${userId}/sprint_sessions']?.docs ?? [];
    expect(savedList.length, 1);
    final saved = savedList.first;
    expect(saved['actualMinutes'], 12);
    expect(saved['plannedMinutes'], 25);
    expect(saved['goalName'], 'Test Goal');
  });
}

// Shim that exposes collection(...).doc(...).collection(...).add(...) chaining against our fake
class _ShimFirestoreForTest {
  final _FakeFirestore _fake;
  final String userId;
  _ShimFirestoreForTest(this._fake, this.userId);

  _ShimCollection collection(String name) => _ShimCollection(_fake, name, userId);
}

class _ShimCollection {
  final _FakeFirestore _fake;
  final String name;
  final String userId;
  _ShimCollection(this._fake, this.name, this.userId);

  _ShimDoc doc(String id) => _ShimDoc(_fake, name, id);
}

class _ShimDoc {
  final _FakeFirestore _fake;
  final String colName;
  final String id;
  _ShimDoc(this._fake, this.colName, this.id);

  _ShimInnerCollection collection(String name) => _ShimInnerCollection(_fake, colName, id, name);
}

class _ShimInnerCollection {
  final _FakeFirestore _fake;
  final String parentCol;
  final String id;
  final String name;
  _ShimInnerCollection(this._fake, this.parentCol, this.id, this.name);

  Future<void> add(Map<String, dynamic> data) async {
    final key = '__${parentCol}/${id}/${name}';
    final col = _fake._top.putIfAbsent(key, () => _FakeCollection());
    await col.add(data);
  }
}
