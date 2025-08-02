import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:circular_countdown_timer/circular_countdown_timer.dart';
import 'dart:async';
import 'gradients.dart';
import 'timer_widget.dart';
import 'sprint_sequence_provider.dart';

class SprintTimerScreen extends ConsumerStatefulWidget {
  final String goalName;
  final String sprintName;
  final int durationMinutes;
  final int sprintIndex;
  
  SprintTimerScreen({
    super.key,
    required this.goalName,
    required this.sprintName,
    required this.durationMinutes,
    required this.sprintIndex,
  }) {
    print('🎯 SprintTimerScreen constructor: durationMinutes=$durationMinutes');
  }

  @override
  ConsumerState<SprintTimerScreen> createState() => _SprintTimerScreenState();
}

class _SprintTimerScreenState extends ConsumerState<SprintTimerScreen> {
  late AudioPlayer _audioPlayer;
  bool _ambientSound = false;
  bool _isPaused = false;
  bool _showAbortButton = true;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    print('🎯 initState: durationMinutes=${widget.durationMinutes}');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hide abort button after 1 minute
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Timer(const Duration(minutes: 1), () {
        if (mounted) {
          setState(() {
            _showAbortButton = false;
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void _toggleAmbient() async {
    setState(() => _ambientSound = !_ambientSound);
    if (_ambientSound) {
      await _audioPlayer.play(AssetSource('soothing-deep-noise.mp3'));
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    } else {
      await _audioPlayer.stop();
    }
  }

  void _onCountdownComplete() async {
    await _saveSprintSession(true); // completed
    _navigateToNextSprint();
  }

  void _stopSession() async {
    await _saveSprintSession(false); // stopped
    _navigateToNextSprint();
  }

  void _abortSession() async {
    await _saveSprintSession(false, aborted: true);
    if (mounted) {
      GoRouter.of(context).go('/sprints');
    }
  }

  void _addTenMinutes() {
    // This will be handled by the TimerWidget
    print('🎯 Add 10 minutes requested');
  }

  Future<void> _saveSprintSession(bool completed, {bool aborted = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // For now, save with planned duration since we don't have access to remaining time
    // TODO: Implement proper duration tracking
    final actualDuration = widget.durationMinutes;
    
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('sprint_sessions')
        .add({
      'goalName': widget.goalName,
      'sprintName': widget.sprintName,
      'sprintIndex': widget.sprintIndex,
      'plannedMinutes': widget.durationMinutes,
      'actualMinutes': actualDuration,
      'completed': completed,
      'aborted': aborted,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  void _navigateToNextSprint() {
    final sequenceState = ref.read(sprintSequenceProvider);
    print('🎯 _navigateToNextSprint: currentIndex=${sequenceState.currentIndex}, hasNext=${sequenceState.hasNextSession}');
    
    if (sequenceState.hasNextSession) {
      // Auto-advance to next session
      ref.read(sprintSequenceProvider.notifier).nextSession();
      final nextSession = sequenceState.sessions[sequenceState.currentIndex + 1];
      print('🎯 _navigateToNextSprint: Next session = ${nextSession.sprintName}, duration=${nextSession.durationMinutes}, index=${nextSession.sprintIndex}');
      
      if (mounted) {
        GoRouter.of(context).go('/sprint-timer?goalName=${Uri.encodeComponent(nextSession.goalName)}&sprintName=${Uri.encodeComponent(nextSession.sprintName)}&durationMinutes=${nextSession.durationMinutes}&sprintIndex=${nextSession.sprintIndex}&phase=${nextSession.phase.name}');
      }
    } else {
      // Sequence complete, go back to sprints screen
      print('🎯 _navigateToNextSprint: Sequence complete, going back to sprints');
      if (mounted) {
        GoRouter.of(context).go('/sprints');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Don't watch the provider to avoid build-time modifications
    print('🎯 SprintTimerScreen build: durationMinutes=${widget.durationMinutes}, sprintName=${widget.sprintName}');
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Header
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => GoRouter.of(context).go('/sprints'),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.goalName,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.sprintName,
                          style: const TextStyle(color: Colors.white54, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  
                ],
              ),
              const SizedBox(height: 40),
              
              // Timer
              Expanded(
                                child: TimerWidget(
                  key: ValueKey('${widget.goalName}-${widget.sprintName}-${widget.durationMinutes}'),
                  durationMinutes: widget.durationMinutes,
                  mode: TimerMode.countdown,
                  onComplete: _onCountdownComplete,
                  onStop: _stopSession,
                  onAbort: _showAbortButton ? _showAbortDialog : null,
                  showAbortButton: _showAbortButton,
                  showAddTimeTooltip: true,
                  showAmbientSound: true,
                  sessionName: widget.goalName,
                  tag: widget.sprintName,
                  isPaused: _isPaused,
                  onPauseResume: (isPaused) {
                    setState(() {
                      _isPaused = isPaused;
                    });
                  },
                  onAddTenMinutes: _addTenMinutes,
                  onToggleAmbient: () => _toggleAmbient(),
                  ambientSound: _ambientSound,
                ),
              ),
              

            ],
          ),
        ),
      ),
    );
  }

  void _showAbortDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('Abort Sprint?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to abort this sprint? This action cannot be undone.',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _abortSession();
            },
            child: const Text('Abort', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
} 