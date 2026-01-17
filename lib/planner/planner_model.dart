import 'dart:async';
import 'dart:core';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

class ScheduledSession {
  final String id;
  final String userId;
  final String title;
  final List<TimerItem> items;
  final String tag;
  final DateTime startAt;
  final String timezone;
  final Recurrence? recurrence;
  final List<int> reminderOffsets;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? seriesId;
  final String? sprintSessionId; // ID of pre-created sprint session

  ScheduledSession({
    required this.id,
    required this.userId,
    required this.title,
    required this.items,
    required this.tag,
    required this.startAt,
    required this.timezone,
    this.recurrence,
    required this.reminderOffsets,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
    this.seriesId,
    this.sprintSessionId,
  });

  factory ScheduledSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ScheduledSession(
      id: doc.id,
      userId: data['userId'],
      title: data['title'],
      items: (data['items'] as List<dynamic>).map((item) => TimerItem.fromMap(item)).toList(),
      tag: data['tag'],
      startAt: (data['startAt'] as Timestamp).toDate(),
      timezone: data['timezone'],
      recurrence: data['recurrence'] != null ? Recurrence.fromMap(data['recurrence']) : null,
      reminderOffsets: List<int>.from(data['reminderOffsets']),
      enabled: data['enabled'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      seriesId: data['seriesId'],
      sprintSessionId: data['sprintSessionId'],
    );
  }

  factory ScheduledSession.fromJson(String json) {
    final data = jsonDecode(json);
    return ScheduledSession(
      id: data['id'],
      userId: data['userId'],
      title: data['title'],
      items: (data['items'] as List<dynamic>).map((item) => TimerItem.fromMap(item)).toList(),
      tag: data['tag'],
      startAt: DateTime.parse(data['startAt']),
      timezone: data['timezone'],
      recurrence: data['recurrence'] != null ? Recurrence.fromMap(data['recurrence']) : null,
      reminderOffsets: List<int>.from(data['reminderOffsets']),
      enabled: data['enabled'],
      createdAt: DateTime.parse(data['createdAt']),
      updatedAt: DateTime.parse(data['updatedAt']),
      seriesId: data['seriesId'],
      sprintSessionId: data['sprintSessionId'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'title': title,
      'items': items.map((item) => item.toMap()).toList(),
      'tag': tag,
      'startAt': Timestamp.fromDate(startAt),
      'timezone': timezone,
      'recurrence': recurrence?.toMap(),
      'reminderOffsets': reminderOffsets,
      'enabled': enabled,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'seriesId': seriesId,
      'sprintSessionId': sprintSessionId,
    };
  }
}

class TimerItem {
  final int durationMinutes;
  final String? label;
  final int? breakAfterMinutes; // Break duration after this session (null for last session)

  TimerItem({required this.durationMinutes, this.label, this.breakAfterMinutes});

  factory TimerItem.fromMap(Map<String, dynamic> map) {
    return TimerItem(
      durationMinutes: map['durationMinutes'],
      label: map['label'],
      breakAfterMinutes: map['breakAfterMinutes'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'durationMinutes': durationMinutes,
      'label': label,
      'breakAfterMinutes': breakAfterMinutes,
    };
  }
}

class Recurrence {
  final String type;
  final List<int>? daysOfWeek;
  final DateTime? endDate;

  Recurrence({required this.type, this.daysOfWeek, this.endDate});

  factory Recurrence.fromMap(Map<String, dynamic> map) {
    return Recurrence(
      type: map['type'],
      daysOfWeek: map['daysOfWeek'] != null ? List<int>.from(map['daysOfWeek']) : null,
      endDate: map['endDate'] != null ? (map['endDate'] as Timestamp).toDate() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'daysOfWeek': daysOfWeek,
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
    };
  }
}

extension RecurrenceHelper on Recurrence {
  DateTime? getNextOccurrence(DateTime current) {
    if (type == 'none') return null;
    if (type == 'daily') {
      return current.add(const Duration(days: 1));
    } else if (type == 'custom' && daysOfWeek != null) {
      final nextDay = daysOfWeek!.firstWhere(
        (day) => day > current.weekday % 7,
        orElse: () => daysOfWeek!.first,
      );
      final daysUntilNext = (nextDay - current.weekday + 7) % 7;
      return current.add(Duration(days: daysUntilNext));
    }
    return null;
  }
}

class PlannerService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> createSession(ScheduledSession session) async {
    await _firestore
        .collection('users')
        .doc(session.userId)
        .collection('scheduled_sessions')
        .doc(session.id)
        .set(session.toFirestore());
  }

  Future<void> updateSession(ScheduledSession session) async {
    await _firestore
        .collection('users')
        .doc(session.userId)
        .collection('scheduled_sessions')
        .doc(session.id)
        .update(session.toFirestore());
  }

  Future<void> deleteSession(String userId, String sessionId) async {
    // Get the session first to check for linked sprint session
    try {
      final sessionDoc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('scheduled_sessions')
          .doc(sessionId)
          .get();
      
      if (sessionDoc.exists) {
        final sessionData = sessionDoc.data() as Map<String, dynamic>;
        final sprintSessionId = sessionData['sprintSessionId'] as String?;
        
        // Delete linked sprint session if it exists
        if (sprintSessionId != null) {
          try {
            await _firestore
                .collection('users')
                .doc(userId)
                .collection('sprint_sessions')
                .doc(sprintSessionId)
                .delete();
            print('✓ Deleted linked sprint session: $sprintSessionId');
          } catch (e) {
            print('✗ Failed to delete linked sprint session: $e');
          }
        }
      }
    } catch (e) {
      print('✗ Error checking for linked sprint session: $e');
    }
    
    // Delete the scheduled session
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('scheduled_sessions')
        .doc(sessionId)
        .delete();
  }

  Stream<List<ScheduledSession>> getSessions(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('scheduled_sessions')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ScheduledSession.fromFirestore(doc))
            .toList());
  }
}