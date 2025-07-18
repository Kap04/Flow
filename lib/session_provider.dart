import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

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