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
import 'dnd_helper.dart';
import 'package:flutter/services.dart';
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
  bool _isPaused = false;
  bool _ambientSound = false;
  bool _showAbortButton = true;
  bool _dndEnabled = false;
  late AudioPlayer _audioPlayer;
  final GlobalKey<TimerWidgetState> _timerKey = GlobalKey<TimerWidgetState>();

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initDndState();
    print('🎯 initState: durationMinutes=${widget.durationMinutes}');
  }

  Future<void> _initDndState() async {
    try {
      final granted = await DndHelper.isAccessGranted();
      if (mounted) setState(() => _dndEnabled = granted);
    } catch (e) {
      // ignore: avoid_print
      print('sprint_timer: failed to query DND access: $e');
    }
  }

  Future<void> _toggleDnd(bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final granted = await DndHelper.isAccessGranted();
      if (!granted) {
        messenger.showSnackBar(SnackBar(
          content: const Text('Please grant Do Not Disturb access in system settings'),
          action: SnackBarAction(label: 'App info', onPressed: () async {
            await DndHelper.openAppSettings();
          }),
        ));
        await DndHelper.openSettings();
        return;
      }
      if (value) {
        await DndHelper.enableDnd();
        if (mounted) setState(() => _dndEnabled = true);
        messenger.showSnackBar(const SnackBar(content: Text('Do Not Disturb enabled')));
      } else {
        await DndHelper.disableDnd();
        if (mounted) setState(() => _dndEnabled = false);
        messenger.showSnackBar(const SnackBar(content: Text('Do Not Disturb disabled')));
      }
    } catch (e) {
      // ignore: avoid_print
      print('sprint_timer: DND toggle error: $e');
      if (e is MissingPluginException) {
        messenger.showSnackBar(const SnackBar(content: Text('DND native handler unavailable — stop and rebuild the app (flutter run) to enable DND functionality')));
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('Failed to toggle Do Not Disturb')));
      }
    }
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
      // Ambient sounds are now user-selected via the Sounds screen and stored in Firestore.
      // For sprint timer we notify the user to choose a sound; playback will be handled by HomeScreen's ambient logic.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ambient playback: open Sounds to choose an ambient sound.')));
      }
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
                  key: _timerKey,
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
                  showSessionName: false, // Hide session name for sprint goals
                  showAmbientSoundButton: false, // Hide ambient sound button since we'll add it separately
                  showControlButtons: false, // Hide control buttons since we'll add them separately
                  timerKey: _timerKey,
                ),
              ),
              
              // Ambient Sound + DND controls (responsive wrap to avoid overflow)
              const SizedBox(height: 16),
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Ambient Sound', style: TextStyle(color: Colors.white, fontSize: 16)),
                        const SizedBox(width: 8),
                        Switch(
                          value: _ambientSound,
                          onChanged: (v) => _toggleAmbient(),
                          activeColor: Colors.grey,
                          trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
                          trackColor: MaterialStateProperty.all(Colors.white24),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Do Not Disturb', style: TextStyle(color: Colors.white, fontSize: 16)),
                        const SizedBox(width: 8),
                        Switch(
                          value: _dndEnabled,
                          onChanged: (v) => _toggleDnd(v),
                          activeColor: Colors.grey,
                          trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
                          trackColor: MaterialStateProperty.all(Colors.white24),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Control buttons at the bottom for sprint goals
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Abort button
                    if (_showAbortButton)
                      GestureDetector(
                        onTap: _showAbortDialog,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                    
                    // Pause/Resume
                    GestureDetector(
                      onTap: () {
                        // Call the TimerWidget's togglePause method
                        _timerKey.currentState?.togglePause();
                      },
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: kAccentGradient,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Icon(
                          _isPaused ? Icons.play_arrow : Icons.pause,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                    
                    // Stop
                    GestureDetector(
                      onTap: _stopSession,
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Center(
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
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