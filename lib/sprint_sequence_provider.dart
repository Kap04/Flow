import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'sprint_goals_screen.dart';

enum SprintPhase { sprint, rest }

class SprintSession {
  final String goalName;
  final String sprintName;
  final int sprintIndex;
  final int durationMinutes;
  final SprintPhase phase;
  final int? breakDuration;

  SprintSession({
    required this.goalName,
    required this.sprintName,
    required this.sprintIndex,
    required this.durationMinutes,
    required this.phase,
    this.breakDuration,
  });
}

class SprintSequenceState {
  final List<SprintSession> sessions;
  final int currentIndex;
  final bool isActive;
  final bool isPaused;
  final bool showAbortButton;

  SprintSequenceState({
    required this.sessions,
    required this.currentIndex,
    required this.isActive,
    required this.isPaused,
    required this.showAbortButton,
  });

  SprintSession? get currentSession => 
      currentIndex >= 0 && currentIndex < sessions.length ? sessions[currentIndex] : null;

  bool get isLastSession => currentIndex >= sessions.length - 1;
  bool get hasNextSession => currentIndex < sessions.length - 1;

  SprintSequenceState copyWith({
    List<SprintSession>? sessions,
    int? currentIndex,
    bool? isActive,
    bool? isPaused,
    bool? showAbortButton,
  }) => SprintSequenceState(
    sessions: sessions ?? this.sessions,
    currentIndex: currentIndex ?? this.currentIndex,
    isActive: isActive ?? this.isActive,
    isPaused: isPaused ?? this.isPaused,
    showAbortButton: showAbortButton ?? this.showAbortButton,
  );
}

class SprintSequenceNotifier extends StateNotifier<SprintSequenceState> {
  SprintSequenceNotifier() : super(SprintSequenceState(
    sessions: [],
    currentIndex: 0,
    isActive: false,
    isPaused: false,
    showAbortButton: true,
  ));

  void startSequence(List<SprintSession> sessions) {
    state = state.copyWith(
      sessions: sessions,
      currentIndex: 0,
      isActive: true,
      isPaused: false,
      showAbortButton: true,
    );
  }

  void nextSession() {
    if (state.hasNextSession) {
      state = state.copyWith(
        currentIndex: state.currentIndex + 1,
        showAbortButton: true,
      );
    } else {
      // Sequence complete
      state = state.copyWith(
        isActive: false,
        isPaused: false,
        showAbortButton: false,
      );
    }
  }

  void pauseResume() {
    state = state.copyWith(isPaused: !state.isPaused);
  }

  void abortSequence() {
    state = state.copyWith(
      isActive: false,
      isPaused: false,
      showAbortButton: false,
    );
  }

  void hideAbortButton() {
    state = state.copyWith(showAbortButton: false);
  }
}

final sprintSequenceProvider = StateNotifierProvider<SprintSequenceNotifier, SprintSequenceState>((ref) => SprintSequenceNotifier());

// Helper function to create sprint sequence from goal state
List<SprintSession> createSprintSequence(String goalName, List<Sprint> sprints) {
  final sessions = <SprintSession>[];
  
  for (int i = 0; i < sprints.length; i++) {
    final sprint = sprints[i];
    
    // Add sprint
    sessions.add(SprintSession(
      goalName: goalName,
      sprintName: sprint.name,
      sprintIndex: i,
      durationMinutes: sprint.duration,
      phase: SprintPhase.sprint,
    ));
    
    // Add break (except after last sprint)
    if (i < sprints.length - 1) {
      sessions.add(SprintSession(
        goalName: goalName,
        sprintName: 'Break',
        sprintIndex: i, // break belongs to the same sprint index
        durationMinutes: sprint.breakDuration,
        phase: SprintPhase.rest,
        breakDuration: sprint.breakDuration,
      ));
    }
  }
  
  return sessions;
} 