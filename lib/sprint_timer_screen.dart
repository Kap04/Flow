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
import 'sprint_persistence.dart';
import 'planner/planner_model.dart';
import 'app_blocking_screen.dart';

class SprintTimerScreen extends ConsumerStatefulWidget {
  final String goalName;
  final String sprintName;
  final int durationMinutes;
  final int sprintIndex;
  final ScheduledSession? scheduledSession;
  final String? preCreatedSprintId;

  SprintTimerScreen({
    super.key,
    required this.goalName,
    required this.sprintName,
    required this.durationMinutes,
    required this.sprintIndex,
    this.scheduledSession,
    this.preCreatedSprintId,
  }) {
    print('🎯 SprintTimerScreen constructor: durationMinutes=$durationMinutes preCreatedSprintId=$preCreatedSprintId');
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
  late final String _sequenceId; // Unique ID for this sprint sequence run
  
  // Track actual minutes for each sprint index
  final Map<int, int> _sprintActualMinutes = {};

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initDndState();
    _notifManager = TimerNotificationManager();
    _sequenceId = DateTime.now().millisecondsSinceEpoch.toString(); // Unique timestamp ID
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
      _notifManager?.start(widget.durationMinutes * 60, title: 'Time Block Timer', body: widget.sprintName);
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
    // Play completion sound
    await _playCompletionSound();
    
    await _saveSprintSession(true); // completed
    _notifManager?.stop();
    await _advanceToNextSession();
  }
  
  Future<void> _playCompletionSound() async {
    try {
      final AudioPlayer soundPlayer = AudioPlayer();
      await soundPlayer.play(AssetSource('sound/timer_complete.mp3'));
      // Don't dispose immediately to let sound play
      Future.delayed(const Duration(seconds: 3), () => soundPlayer.dispose());
    } catch (e) {
      print('Error playing completion sound: $e');
    }
  }

  Future<void> _advanceToNextSession() async {
    final before = ref.read(sprintSequenceProvider);
    if (!before.hasNextSession) {
      // sequence finished — show summary dialog before returning to sprints list
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => SprintSummaryDialog(
            goalName: widget.goalName, 
            sessions: before.sessions, 
            actualMinutesMap: _sprintActualMinutes, // Pass in-memory actual minutes
          ),
        );
        // after dialog closed, pop this screen to go back to sprint list
        if (mounted) context.pop();
      }
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
      _notifManager?.start(session.durationMinutes * 60, title: 'Time Block Timer', body: session.sprintName);
    });
  }

  void _stopSession() async {
    await _saveSprintSession(false); // stopped
    _notifManager?.stop();
    _navigateToNextSprint();
  }

  void _skipSession() async {
    // Skip the current sprint: save it as skipped with actual duration, then advance in-place.
    await _saveSprintSession(false); // skipped
    _notifManager?.stop();
    final before = ref.read(sprintSequenceProvider);
    if (before.hasNextSession) {
      // Advance provider and apply next session in-place so the TimerWidget updates immediately
      ref.read(sprintSequenceProvider.notifier).nextSession();
      final after = ref.read(sprintSequenceProvider);
      final next = after.currentSession;
      if (next != null) {
        _applySession(next);
        return;
      }
    }
    // If no next session, show final summary
    await _showSprintSummary();
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
    // Determine the session we're saving: prefer the in-memory current session
    final seq = ref.read(sprintSequenceProvider);
    final session = _currentSession ?? seq.currentSession;
    
    // Don't save break sessions to database
    if (session?.phase == SprintPhase.rest) {
      print('⏭️ Skipping database save for break session');
      return;
    }

    // Attempt to read actual duration from the TimerWidget if available
    int actualDuration = session?.durationMinutes ?? widget.durationMinutes;
    try {
      final val = _timerKey.currentState?.getActualMinutes();
      if (val != null) actualDuration = val;
    } catch (_) {}
    
    // Don't save sessions with 0 actual minutes (skipped/aborted immediately)
    if (actualDuration == 0) {
      print('⏭️ Skipping database save for session with 0 actual minutes');
      return;
    }
    
    // Store actual minutes for this sprint index in memory
    final sprintIdx = session?.sprintIndex ?? widget.sprintIndex;
    _sprintActualMinutes[sprintIdx] = actualDuration;

    final saveData = {
      'goalName': session?.goalName ?? widget.goalName,
      'sprintName': session?.sprintName ?? widget.sprintName,
      'sprintIndex': sprintIdx,
      'plannedMinutes': session?.durationMinutes ?? widget.durationMinutes,
      'actualMinutes': actualDuration,
      'completed': completed,
      'aborted': aborted,
      'sequenceId': _sequenceId, // Add unique sequence ID
      'timestamp': FieldValue.serverTimestamp(),
      'tag': session?.tag ?? 'Unset',
      'duration': actualDuration,
      'createdAt': FieldValue.serverTimestamp(),
    };
    
    print('💾 Saving sprint session: tag=${saveData['tag']}, duration=$actualDuration, completed=$completed');

    await saveSprintSessionRecord(userId: user.uid, data: saveData);
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

  // Dialog that summarizes a completed sprint sequence
  Future<void> _showSprintSummary() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SprintSummaryDialog(
        goalName: widget.goalName,
        sessions: ref.read(sprintSequenceProvider).sessions,
        actualMinutesMap: _sprintActualMinutes, // Pass in-memory actual minutes
      ),
    );

    // If user closed with X (null), keep the sprint timer running.
    if (result == null) return;

    // If result is true or false, user made a choice; end the sprint session sequence.
    _notifManager?.stop();
    if (mounted) {
      context.pop();
    }
  }

  Future<void> _showSprintPausePreview() async {
    final seq = ref.read(sprintSequenceProvider);
    final current = _currentSession ?? seq.currentSession;
    final sessionName = current?.sprintName ?? widget.sprintName;
    final planned = current?.durationMinutes ?? widget.durationMinutes;
    
    // Get actual elapsed minutes from TimerWidget
    int actual = planned;
    try {
      final val = _timerKey.currentState?.getActualMinutes();
      if (val != null) actual = val;
    } catch (_) {}

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 40),
                  const Expanded(
                    child: Text(
                      'End Session?',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(ctx).pop(null),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Session name', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  Flexible(
                    child: Text(sessionName, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Duration', style: TextStyle(color: Colors.white54)),
                Text('$actual min', style: const TextStyle(color: Colors.white)),
              ]),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Planned', style: TextStyle(color: Colors.white54)),
                Text('$planned min', style: const TextStyle(color: Colors.white)),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Back to session', style: TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5C5C),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('End Session', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );

    if (result == true) {
      // User chose to end — save the current session then show the full sprint summary dialog
      await _saveSprintSession(true);
      await _showSprintSummary();
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
                    isBreak: _currentSession?.phase == SprintPhase.rest,
                  ),
              ),
              
              // Ambient Sound + DND controls
              const SizedBox(height: 16),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Ambient sound toggle
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.music_note, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Switch(
                          value: _ambientSound,
                          onChanged: (v) => _toggleAmbient(),
                          activeColor: Colors.grey,
                          trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                          trackColor: WidgetStateProperty.all(Colors.white24),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // DND toggle
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.do_not_disturb_on, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Switch(
                          value: _dndEnabled,
                          onChanged: (v) => _toggleDnd(v),
                          activeColor: Colors.grey,
                          trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                          trackColor: WidgetStateProperty.all(Colors.white24),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Block Apps button
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => AppBlockingScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.block, size: 18, color: Colors.white),
                      label: const Text(
                        'Block Apps',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366f1),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),

              // Buttons row: Skip current sprint or end entire sprint session
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _skipSession,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        border: Border.all(
                          color: const Color(0x66FFFFFF),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: const Text(
                        'Skip Session',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: _showSprintPausePreview,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0x14FF4B4B),
                        border: Border.all(
                          color: const Color(0x66FF4B4B),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: const Text(
                        'End Session',
                        style: TextStyle(color: Color(0xFFFF5C5C), fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Dialog that summarizes a completed sprint sequence
class SprintSummaryDialog extends ConsumerStatefulWidget {
  final String goalName;
  final List<SprintSession> sessions;
  final Map<int, int> actualMinutesMap; // Map of sprintIndex -> actual minutes

  const SprintSummaryDialog({
    Key? key, 
    required this.goalName, 
    required this.sessions, 
    required this.actualMinutesMap,
  }) : super(key: key);

  @override
  ConsumerState<SprintSummaryDialog> createState() => _SprintSummaryDialogState();
}

class _SprintSummaryDialogState extends ConsumerState<SprintSummaryDialog> {
  bool _processing = false;
  String? _error;

  Future<void> _saveSprintSessions() async {
    setState(() { _processing = true; _error = null; });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');

      // Save all sprint sessions (they were already saved individually, just need to update focus score)
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('sessions')
          .orderBy('endTime', descending: true)
          .limit(50)
          .get();
      
      final allSessions = snap.docs.map((d) => d.data()).toList();
      if (allSessions.isNotEmpty) {
        final totalDuration = allSessions.fold<num>(0, (sum, s) => sum + (s['duration'] ?? 0));
        final focusScore = totalDuration / allSessions.length;
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {'focusScore': double.parse(focusScore.toStringAsFixed(2))}, 
          SetOptions(merge: true)
        );
      }
      
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _processing = false; });
    }
  }

  void _dontSave() {
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    // No Firestore query — use the in-memory actual minutes map
    final sprintOnly = widget.sessions.where((s) => s.phase == SprintPhase.sprint).toList();
    
    // Calculate total focused time from actual minutes map
    int totalFocused = 0;
    for (final s in sprintOnly) {
      final actual = widget.actualMinutesMap[s.sprintIndex] ?? 0;
      totalFocused += actual;
    }

    final sprintWidgets = <Widget>[];
    for (int i = 0; i < sprintOnly.length; i++) {
      final s = sprintOnly[i];
      final actualMinutes = widget.actualMinutesMap[s.sprintIndex] ?? 0;
      final statusIcon = actualMinutes > 0 ? '✅' : '—';
      
      sprintWidgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Block ${s.sprintIndex + 1}',
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ),
              Text(
                '$actualMinutes min',
                style: const TextStyle(color: Color(0xFF1E88E5), fontSize: 15),
              ),
              const SizedBox(width: 12),
              Text(
                statusIcon,
                style: const TextStyle(fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: title + close
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 32),
                const Expanded(
                  child: Text(
                    'Session Summary',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(null),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white70,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Main Goal
                Text(
                  widget.goalName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),
                
                // Time Block Breakdown
                const Text(
                  'Time Block Breakdown',
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const SizedBox(height: 12),
                ...sprintWidgets,
                const SizedBox(height: 24),
                
                // Total Focused Time
                RichText(
                  text: TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Total Focused Time: ',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      TextSpan(
                        text: '$totalFocused',
                        style: const TextStyle(
                          color: Color(0xFF1E88E5),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const TextSpan(
                        text: ' minutes',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    ],
                  ),
                ),
                
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                
                const SizedBox(height: 24),
                
                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _processing ? null : _dontSave,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white30),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: const Text(
                          "Don't Save",
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _processing ? null : _saveSprintSessions,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E88E5),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: _processing
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Save',
                                style: TextStyle(color: Colors.white, fontSize: 16),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
  }
}
