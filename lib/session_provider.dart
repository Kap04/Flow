import 'package:flutter_riverpod/flutter_riverpod.dart';
// removed unused material import
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SessionState {
  final int duration; // total session length in minutes
  final int secondsLeft;
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

  void start({required int duration, required String tag, required bool ambient}) {
    state = SessionState(
      duration: duration,
      secondsLeft: duration * 60,
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

// Focus Score Provider
final focusScoreProvider = FutureProvider<double>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return 0.0;
  final lookback = ref.watch(_lookbackProvider);
  final formula = ref.watch(_formulaProvider);
  // final stretch = ref.watch(_stretchProvider); // Placeholder for future use
  final snap = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('sessions')
      .orderBy('endTime', descending: true)
      .limit(lookback)
      .get();
  final sessions = snap.docs
      .map((doc) => doc.data())
      .where((data) =>
          (data['duration'] ?? 0) >= (ref.read(outlierThresholdProvider)) &&
          (data['aborted'] != true))
      .toList();
  if (sessions.isEmpty) return 0.0;
  if (formula == 'simple') {
    final avg = sessions.map((s) => (s['duration'] ?? 0) as num).reduce((a, b) => a + b) / sessions.length;
    return avg.toDouble();
  } else if (formula == 'median') {
    final sorted = sessions.map((s) => (s['duration'] ?? 0) as num).toList()..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length % 2 == 1) {
      return sorted[mid].toDouble();
    } else {
      return ((sorted[mid - 1] + sorted[mid]) / 2).toDouble();
    }
  } else {
    // weighted
    final weights = [0.4, 0.25, 0.15, 0.12, 0.08];
    double score = 0.0;
    double totalWeight = 0.0;
    for (int i = 0; i < sessions.length && i < weights.length; i++) {
      score += (sessions[i]['duration'] ?? 0) * weights[i];
      totalWeight += weights[i];
    }
    if (sessions.length > weights.length) {
      for (int i = weights.length; i < sessions.length; i++) {
        score += (sessions[i]['duration'] ?? 0) * 0.05;
        totalWeight += 0.05;
      }
    }
    return score / totalWeight;
  }
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