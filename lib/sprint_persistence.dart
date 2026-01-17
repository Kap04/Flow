import 'package:cloud_firestore/cloud_firestore.dart';

// Accept a dynamic firestore instance to allow passing a lightweight fake in tests.
Future<dynamic> saveSprintSessionRecord({
  required String userId,
  required Map<String, dynamic> data,
  dynamic firestore,
}) async {
  final db = firestore ?? FirebaseFirestore.instance;
  // The real Firebase API returns a Future<DocumentReference> from add,
  // but to keep this helper testable we return whatever the underlying
  // implementation returns (dynamic).
  final ref = await db.collection('users').doc(userId).collection('sprint_sessions').add(data);
  return ref;
}
