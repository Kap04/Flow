import 'package:flutter_riverpod/flutter_riverpod.dart';
// removed unused material import
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SessionState {
  final int duration; // total session length in minutes
  final int secondsLeft;
  final String sessionName;
  final String tag;
  final bool ambient;
  final bool running;
  final bool paused;
  final bool distracted;
  final DateTime? startTime;
  final DateTime? endTime;

  SessionState({
    required this.duration,
    required this.secondsLeft,
    required this.sessionName,
    required this.tag,
    required this.ambient,
    required this.running,
    required this.paused,
    required this.distracted,
    this.startTime,
    this.endTime,
  });

  SessionState copyWith({
    int? duration,
    int? secondsLeft,
    String? sessionName,
    String? tag,
    bool? ambient,
    bool? running,
    bool? paused,
    bool? distracted,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    return SessionState(
      duration: duration ?? this.duration,
      secondsLeft: secondsLeft ?? this.secondsLeft,
      sessionName: sessionName ?? this.sessionName,
      tag: tag ?? this.tag,
      ambient: ambient ?? this.ambient,
      running: running ?? this.running,
      paused: paused ?? this.paused,
      distracted: distracted ?? this.distracted,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }
}

class SessionNotifier extends StateNotifier<SessionState?> {
  SessionNotifier() : super(null);

  void start({required int duration, required String sessionName, required String tag, required bool ambient}) {
    state = SessionState(
      duration: duration,
      secondsLeft: duration * 60,
      sessionName: sessionName,
      tag: tag,
      ambient: ambient,
      running: true,
      paused: false,
      distracted: false,
      startTime: DateTime.now(),
      endTime: null,
    );
  }

  void tick() {
    if (state == null || !state!.running || state!.paused) return;
    if (state!.secondsLeft > 0) {
      state = state!.copyWith(secondsLeft: state!.secondsLeft - 1);
    } else {
      endSession();
    }
  }

  void pause() {
    if (state != null) state = state!.copyWith(paused: true);
  }

  void resume() {
    if (state != null) state = state!.copyWith(paused: false);
  }

  void endSession() {
    if (state != null) state = state!.copyWith(running: false, endTime: DateTime.now());
  }

  void markDistracted() {
    if (state != null) state = state!.copyWith(distracted: true);
  }

  void reset() {
    state = null;
  }
}

final sessionProvider = StateNotifierProvider<SessionNotifier, SessionState?>((ref) => SessionNotifier());

// Focus Score Provider - Simple average of all sessions
final focusScoreProvider = FutureProvider<double>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return 0.0;
  
  final snap = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('sessions')
      .orderBy('endTime', descending: true)
      .limit(50) // Look at last 50 sessions
      .get();
  
  // Include ALL sessions - no filtering by duration or aborted status
  final sessions = snap.docs.map((doc) => doc.data()).toList();
  
  if (sessions.isEmpty) return 0.0;
  
  // Simple average of all session durations
  final totalDuration = sessions.fold<num>(0, (sum, s) => sum + (s['duration'] ?? 0));
  return (totalDuration / sessions.length).toDouble();
});

// Outlier threshold provider (default 2 min)
final outlierThresholdProvider = StateProvider<int>((ref) => 2);

// Advanced settings providers
final _formulaProvider = StateProvider<String>((ref) => 'weighted');
final _lookbackProvider = StateProvider<int>((ref) => 5);
final _stretchProvider = StateProvider<String>((ref) => 'adaptive');

// Adaptive stretch session length provider
final stretchSessionProvider = FutureProvider<int>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return 0;
  final focusScore = await ref.watch(focusScoreProvider.future);
  final snap = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('sessions')
      .orderBy('endTime', descending: true)
      .limit(3)
      .get();
  final sessions = snap.docs
      .map((doc) => doc.data())
      .where((data) => (data['duration'] ?? 0) > 0 && (data['aborted'] != true) && (data['planned'] ?? 0) > 0)
      .toList();
  if (focusScore == 0.0) return 0;
  final stretchSetting = ref.watch(_stretchProvider);
  if (stretchSetting == 'off') {
    return focusScore.round();
  } else if (stretchSetting == 'fixed') {
    return (focusScore * 1.05).round();
  } else {
    // adaptive
    if (sessions.isEmpty) return focusScore.round();
    int completed = 0;
    for (final s in sessions) {
      final planned = (s['planned'] ?? s['duration'] ?? 0) as num;
      final actual = (s['duration'] ?? 0) as num;
      if (planned == 0) continue;
      if (actual / planned >= 0.8) completed++;
    }
    final rate = completed / sessions.length;
    double stretch = focusScore;
    if (rate >= 0.8) {
      stretch = focusScore * 1.10;
    } else if (rate >= 0.5) {
      stretch = focusScore * 1.05;
    } else {
      stretch = focusScore * 0.95;
    }
    return stretch.round();
  }
});

// Completion rate provider for analytics
final completionRateProvider = FutureProvider<double>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return 0.0;
  final snap = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('sessions')
      .orderBy('endTime', descending: true)
      .limit(10)
      .get();
  final sessions = snap.docs
      .map((doc) => doc.data())
      .where((data) => (data['duration'] ?? 0) > 0 && (data['aborted'] != true) && (data['planned'] ?? 0) > 0)
      .toList();
  if (sessions.isEmpty) return 0.0;
  int completed = 0;
  for (final s in sessions) {
    final planned = (s['planned'] ?? s['duration'] ?? 0) as num;
    final actual = (s['duration'] ?? 0) as num;
    if (planned == 0) continue;
    if (actual / planned >= 0.8) completed++;
  }
  return completed / sessions.length;
}); 