import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// removed unused import: circular_countdown_timer
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'gradients.dart';
import 'timer_widget.dart';
import 'dnd_helper.dart';
import 'package:flutter/services.dart';
import 'sprint_sequence_provider.dart';
import 'timer_notification_manager.dart';
// removed unused import: notification_service.dart

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

// Minimalistic header that shows the main goal, the current sprint line, and a compact dot indicator.
class _SprintHeader extends StatelessWidget {
  final String goalTitle;
  final List<SprintSession> sessions;
  final int currentIndex;
  final double dotSize;

  const _SprintHeader({
    Key? key,
    required this.goalTitle,
    required this.sessions,
    required this.currentIndex,
    this.dotSize = 8.0,
  }) : super(key: key);

  static const Color _activeBlue = Color(0xFF66B8FF);

  @override
  Widget build(BuildContext context) {
    // derive sprint-only list
    final sprintSessions = sessions.where((s) => s.phase == SprintPhase.sprint).toList();

    // determine active sprint index among sprintSessions
    int activeSprint = -1;
    if (currentIndex >= 0 && currentIndex < sessions.length) {
      final cs = sessions[currentIndex];
      if (cs.phase == SprintPhase.sprint) {
        activeSprint = cs.sprintIndex;
      } else {
        // during a rest slot, treat the next sprint as the active/upcoming one where possible
        activeSprint = (cs.sprintIndex < sprintSessions.length) ? cs.sprintIndex : sprintSessions.length - 1;
      }
    }

    // clamp
    if (activeSprint < 0 && sprintSessions.isNotEmpty) activeSprint = 0;

    final sprintCount = sprintSessions.length;

  final sprintLabel = (activeSprint >= 0 && activeSprint < sprintCount)
    ? sprintSessions[activeSprint].sprintName
    : (sessions.isNotEmpty ? sessions[currentIndex].sprintName : 'Sprint');

  Widget _dotForIndex(int idx) {
      if (idx < activeSprint) {
        // completed (lighter)
        return Container(width: dotSize, height: dotSize, decoration: BoxDecoration(color: Colors.white70, shape: BoxShape.circle));
      }
      if (idx == activeSprint) {
        // ongoing
        return Container(width: dotSize, height: dotSize, decoration: const BoxDecoration(color: _activeBlue, shape: BoxShape.circle));
      }
      // pending
      return Container(
        width: dotSize,
        height: dotSize,
        decoration: BoxDecoration(
          color: Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.shade600, width: 1.0),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // main goal
        Text(goalTitle, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        // sprint name (blue)
        Text(sprintLabel, style: const TextStyle(color: _SprintHeader._activeBlue, fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        // dots left-aligned below
        Row(mainAxisSize: MainAxisSize.min, children: List.generate(sprintCount, (i) => Padding(padding: const EdgeInsets.only(right:6.0), child: _dotForIndex(i))),),
      ],
    );
  }
}

class _SprintTimerScreenState extends ConsumerState<SprintTimerScreen> {
  bool _isPaused = false;
  bool _ambientSound = false;
  bool _showAbortButton = true;
  bool _dndEnabled = false;
  late AudioPlayer _audioPlayer;
  final GlobalKey<TimerWidgetState> _timerKey = GlobalKey<TimerWidgetState>();
  SprintSession? _currentSession;
  TimerNotificationManager? _notifManager;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initDndState();
    _notifManager = TimerNotificationManager();
    print('🎯 initState: durationMinutes=${widget.durationMinutes}');
    // Initialize current session from provider if available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final seq = ref.read(sprintSequenceProvider);
      if (seq.sessions.isNotEmpty) {
        final cs = seq.currentSession ?? seq.sessions.first;
        _applySession(cs);
      } else {
        // fallback to route-provided widget values
        _currentSession = SprintSession(goalName: widget.goalName, sprintName: widget.sprintName, sprintIndex: widget.sprintIndex, durationMinutes: widget.durationMinutes, phase: SprintPhase.sprint);
      }
      // Start notification when session starts
      _notifManager?.start(widget.durationMinutes * 60, title: 'Sprint Timer', body: widget.sprintName);
    });
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
    _notifManager?.stop();
    super.dispose();
  }

  void _toggleAmbient() async {
    // Toggle request: attempt to enable playback first, then set state if successful.
    final enableRequest = !_ambientSound;
    if (enableRequest) {
      // Check if a sound is selected (we store the selected sound id in 'selectedSoundId')
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final selectedSoundId = userDoc.data()?['selectedSoundId'] as String?;
      if (selectedSoundId == null || selectedSoundId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ambient playback: open Sounds to choose an ambient sound.')));
        }
      } else {
        // Fetch the sound document and play its downloadUrl (if present)
        try {
          final soundDoc = await FirebaseFirestore.instance.collection('sounds').doc(selectedSoundId).get();
          final sdata = soundDoc.data() ?? {};
          final downloadUrl = (sdata['downloadUrl'] ?? sdata['url'] ?? sdata['storagePath']) as String?;
          // Try to play a locally downloaded file first (search for any file starting with the sound id)
          bool played = false;
          try {
            final dir = await getApplicationDocumentsDirectory();
            final files = Directory(dir.path).listSync().whereType<File>().toList();
            final match = files.firstWhere(
              (f) => f.path.split(Platform.pathSeparator).last.startsWith('$selectedSoundId.'),
              orElse: () => File(''),
            );
            if (match.path.isNotEmpty && await match.exists()) {
              await _audioPlayer.stop();
              await _audioPlayer.play(DeviceFileSource(match.path));
              played = true;
            }
          } catch (_) {}

          if (!played) {
            if (downloadUrl != null && downloadUrl.isNotEmpty) {
              try {
                await _audioPlayer.stop();
                // ensure ambient loops
                await _audioPlayer.setReleaseMode(ReleaseMode.loop);
                await _audioPlayer.play(UrlSource(downloadUrl));
                played = true;
              } catch (e) {
                // capture failure
                // ignore: avoid_print
                print('sprint_timer: failed to stream url: $e');
              }
            }
          }

          if (played) {
            if (mounted) setState(() => _ambientSound = true);
          } else {
            // Provide diagnostic feedback so we can see why playback failed
            final msg = 'Failed to play selected ambient sound (${selectedSoundId ?? 'no-id'})${downloadUrl != null ? ' — url present' : ' — no url'}';
            // ignore: avoid_print
            print('sprint_timer: $msg');
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
          }
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to play selected ambient sound')));
        }
      }
    } else {
      // disable
      await _audioPlayer.stop();
      if (mounted) setState(() => _ambientSound = false);
    }
  }

  void _onCountdownComplete() async {
    await _saveSprintSession(true); // completed
    _notifManager?.stop();
    await _advanceToNextSession();
  }

  Future<void> _advanceToNextSession() async {
    final before = ref.read(sprintSequenceProvider);
    if (!before.hasNextSession) {
      // sequence finished
      if (mounted) context.pop();
      return;
    }
    // advance provider
    ref.read(sprintSequenceProvider.notifier).nextSession();
    // read fresh
    final after = ref.read(sprintSequenceProvider);
    final next = after.currentSession;
    if (next == null) {
      if (mounted) context.pop();
      return;
    }
    // Apply the next session in-place (restart timer widget)
    _applySession(next);
  }

  void _applySession(SprintSession session) {
    _currentSession = session;
    // Update UI elements (goal/sprint text) by calling setState
    if (mounted) setState(() {});
    // Ask the TimerWidget to start the new session
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _timerKey.currentState?.startNewSession(sessionName: session.goalName, tag: session.sprintName, durationMinutes: session.durationMinutes, mode: TimerMode.countdown);
      } catch (e) {
        // ignore: avoid_print
        print('sprint_timer: failed to start new session on timer widget: $e');
        // fallback: navigate to route for full rebuild
        if (mounted) GoRouter.of(context).go('/sprint-timer?goalName=${Uri.encodeComponent(session.goalName)}&sprintName=${Uri.encodeComponent(session.sprintName)}&durationMinutes=${session.durationMinutes}&sprintIndex=${session.sprintIndex}&phase=${session.phase.name}');
      }
      // restart notification manager for this session
      _notifManager?.start(session.durationMinutes * 60, title: 'Sprint Timer', body: session.sprintName);
    });
  }

  void _stopSession() async {
    await _saveSprintSession(false); // stopped
    _notifManager?.stop();
    _navigateToNextSprint();
  }

  void _abortSession() async {
    await _saveSprintSession(false, aborted: true);
    _notifManager?.stop();
    if (mounted) {
      context.pop();
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
    final before = ref.read(sprintSequenceProvider);
    print('🎯 _navigateToNextSprint: currentIndex=${before.currentIndex}, hasNext=${before.hasNextSession}');

    if (before.hasNextSession) {
      // Advance provider
      ref.read(sprintSequenceProvider.notifier).nextSession();
      // read fresh state
      final after = ref.read(sprintSequenceProvider);
      final nextSession = after.currentSession;
      if (nextSession == null) {
        // fallback
        if (mounted) context.pop();
        return;
      }
      print('🎯 _navigateToNextSprint: Next session = ${nextSession.sprintName}, duration=${nextSession.durationMinutes}, index=${nextSession.sprintIndex}, phase=${nextSession.phase}');
      if (mounted) {
        GoRouter.of(context).go('/sprint-timer?goalName=${Uri.encodeComponent(nextSession.goalName)}&sprintName=${Uri.encodeComponent(nextSession.sprintName)}&durationMinutes=${nextSession.durationMinutes}&sprintIndex=${nextSession.sprintIndex}&phase=${nextSession.phase.name}');
      }
    } else {
      // Sequence complete, go back to sprints screen
      print('🎯 _navigateToNextSprint: Sequence complete, going back to sprints');
      if (mounted) {
        context.pop();
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
              // Header: minimal sprint header (no close button)
              Row(
                children: [
                  // Use provider to build the header reactively
                  Expanded(
                    child: Consumer(builder: (context, wRef, _) {
                      final seq = wRef.watch(sprintSequenceProvider);
                      final goalTitle = widget.goalName.isNotEmpty ? widget.goalName : (seq.sessions.isNotEmpty ? seq.sessions.first.goalName : 'Goal');
                      return _SprintHeader(goalTitle: goalTitle, sessions: seq.sessions, currentIndex: seq.currentIndex, dotSize: 8.0);
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              
              // Timer
              Expanded(
                  child: TimerWidget(
                    key: _timerKey,
                    durationMinutes: _currentSession?.durationMinutes ?? widget.durationMinutes,
                    mode: TimerMode.countdown,
                    onComplete: _onCountdownComplete,
                    onStop: _stopSession,
                    onAbort: _showAbortButton ? _showAbortDialog : null,
                    showAbortButton: _showAbortButton,
                    showAddTimeTooltip: true,
                    showAmbientSound: true,
                    sessionName: _currentSession?.goalName ?? widget.goalName,
                    tag: _currentSession?.sprintName ?? widget.sprintName,
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
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
                    const SizedBox(height: 16),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
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
                    const SizedBox(height: 12),
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