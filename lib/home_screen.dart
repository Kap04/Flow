import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'session_provider.dart';
// removed unused imports
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:circular_countdown_timer/circular_countdown_timer.dart';
import 'gradients.dart';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'timer_widget.dart';
import 'app_drawer.dart';
import 'dnd_helper.dart';
import 'package:flutter/services.dart';
import 'timer_notification_manager.dart';
import 'session_summary_dialog.dart';
// removed unused import: notification_service.dart

const List<String> kPredefinedTags = [
  'Unset',
  'Study',
  'Work',
  'Reading',
  'Rest',
  'Other',
];

// When true, pressing Back on the Home screen with no back history will
// show a confirmation dialog before exiting the app. Set to false to exit immediately.
const bool kConfirmExitOnHome = true;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _distracted = false;
  int _minutes = 25;
  String _selectedTag = kPredefinedTags[0];
  String? _customTag; // null means no custom tag active
  bool _showCustomTagInput = false;
  bool _ambientSound = false;
  bool _dndEnabled = false;
  bool _isCountingDown = false;
  bool _isPaused = false;
  late CountDownController _countDownController;
  DateTime? _sessionStart;
  int _focusMode = 0; // 0 = countdown, 1 = count up
  String _sessionName = '';
  int _countUpSeconds = 0;
  Timer? _countUpTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _aborted = false;
  DateTime? _sessionStartTime;
  Timer? _abortTimer;
  int? _lastStretch;
  late FixedExtentScrollController _minutesController;
  bool _programmaticDialSet = false;
  bool _stretchAppliedOnce = false;
  bool _userManuallyChangedDials = false;
  int? _preCountUpMinutes;
  final GlobalKey<TimerWidgetState> _timerKey = GlobalKey<TimerWidgetState>();
  TimerNotificationManager? _notifManager;
  
  // Predefined minute values
  static const List<int> _availableMinutes = [
    15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100, 105, 110, 115, 120
  ];
  
  int get _selectedMinutesIndex => _availableMinutes.indexOf(_minutes).clamp(0, _availableMinutes.length - 1);

  @override
  void initState() {
    super.initState();
    _countDownController = CountDownController();
    _minutesController = FixedExtentScrollController(initialItem: _selectedMinutesIndex);
    _notifManager = TimerNotificationManager();
    // Defer prefs and DND checks until after first frame to avoid blocking the
    // main thread during app startup which can cause skipped frames on cold
    // launch (especially on emulators).
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPrefs());
  }

  Future<void> _showEndSessionPreview() async {
    // Compute current duration without stopping the timer
    int duration = 0;
    final int planned = _minutes;
    if (_focusMode == 0) {
      if (_sessionStart != null) {
        duration = DateTime.now().difference(_sessionStart!).inSeconds ~/ 60;
        if (duration < 0) duration = 0;
        if (planned > 0 && duration > planned) duration = planned;
      }
    } else {
      duration = (_countUpSeconds ~/ 60);
    }

    final sessionName = _sessionName.isNotEmpty ? _sessionName : 'Untitled';
    final tag = _customTag ?? _selectedTag;
    final distracted = _distracted;

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
                  const Text(
                    'Session name',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  Flexible(
                    child: Text(
                      sessionName,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Duration', style: TextStyle(color: Colors.white54)),
                Text('$duration min', style: const TextStyle(color: Colors.white)),
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
      // User chose to end — call existing stop logic
      _stopSession();
    }
    // if null or false, just return and let timer continue
  }

  @override
  void dispose() {
    _countUpTimer?.cancel();
    _audioPlayer.dispose();
    _abortTimer?.cancel();
    _minutesController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedTag = prefs.getString('selectedTag') ?? kPredefinedTags[0];
      _ambientSound = prefs.getBool('ambientSound') ?? false;
    });
    // Query DND access state and reflect in UI
    try {
      final granted = await DndHelper.isAccessGranted();
      setState(() => _dndEnabled = granted);
    } catch (e) {
      // ignore: avoid_print
      print('home_screen: failed to query DND access: $e');
    }
    // Ensure DND is off by default
    setState(() => _dndEnabled = false);
  }

  void _setDialsFromStretch(int stretch, {bool force = false}) {
    // If stretch changed, allow re-application
    if (_lastStretch != stretch) {
      _stretchAppliedOnce = false;
    }
    if (!_isCountingDown && stretch > 0 && (!_stretchAppliedOnce || force)) {
      _programmaticDialSet = true;
      // If we're applying programmatically, clear the user's manual-change flag
      if (!force) {
        // normal programmatic apply (reactive) should clear manual flag
        _userManuallyChangedDials = false;
      } else {
        // forced reapply should only occur when callers checked the manual flag
        // externally; do not clear it here to avoid overriding an explicit user change.
      }
      
      // Find the closest available minute value
      int targetMinutes = stretch.clamp(15, 120);
      int closestIndex = 0;
      int smallestDiff = (_availableMinutes[0] - targetMinutes).abs();
      
      for (int i = 1; i < _availableMinutes.length; i++) {
        int diff = (_availableMinutes[i] - targetMinutes).abs();
        if (diff < smallestDiff) {
          smallestDiff = diff;
          closestIndex = i;
        }
      }
      
      setState(() {
        _minutes = _availableMinutes[closestIndex];
        _lastStretch = stretch;
      });
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_programmaticDialSet) {
          _minutesController.jumpToItem(closestIndex);
        }
      });
      _stretchAppliedOnce = true;
    }
  }

  void _startFlow() {
    setState(() {
      _isCountingDown = true;
      _isPaused = false;
      _sessionStart = DateTime.now();
      _sessionStartTime = DateTime.now();
      _distracted = false;
      _aborted = false;
      // start ambient playback if enabled and a sound is selected
      if (_ambientSound) {
        _startAmbientPlayback();
      }
      if (_focusMode == 1) {
        _countUpSeconds = 0;
        _countUpTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!_isPaused) {
            setState(() => _countUpSeconds++);
          }
        });
      }
      // Start notification for pomodoro timer
      final totalSeconds = (_focusMode == 0)
          ? _minutes * 60
          : 0;
      _notifManager?.start(
        totalSeconds,
        title: 'Timer',
        body: _sessionName.isNotEmpty
            ? _sessionName
            : (_customTag ?? _selectedTag),
      );
      _abortTimer?.cancel();
      _abortTimer = Timer(const Duration(seconds: 60), () {
        setState(() {
          // This will trigger a rebuild and hide the abort button
        });
      });
    });
  }

  Future<void> _playCompletionSound() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sound/timer_complete.mp3'));
    } catch (e) {
      print('Error playing completion sound: $e');
    }
  }

  void _onCountdownComplete() {
    // Play completion sound
    _playCompletionSound();
    
    // Capture session data before resetting state
    final sessionName = _sessionName.isNotEmpty ? _sessionName : 'Untitled';
    final tag = _customTag ?? _selectedTag;
    final durationMinutes = _minutes;
    final distracted = _distracted;
    final completedAt = DateTime.now();
    
    // Stop ambient playback and notifications
    _stopAmbientPlayback();
    _abortTimer?.cancel();
    _notifManager?.stop();
    
    // Reset state
    setState(() {
      _isCountingDown = false;
      _isPaused = false;
      _sessionStart = null;
    });
    
    // Show summary dialog (which handles saving)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SessionSummaryDialog(
        sessionName: sessionName,
        tag: tag,
        durationMinutes: durationMinutes,
        distracted: distracted,
        completedAt: completedAt,
      ),
    );
  }

  void _stopSession() {
    // Calculate duration
    int duration = 0;
    int planned = _minutes;
    if (_focusMode == 0) {
      if (_sessionStart != null) {
        duration = DateTime.now().difference(_sessionStart!).inSeconds ~/ 60;
        if (duration > planned) duration = planned;
        if (duration < 0) duration = 0;
      }
    } else {
      duration = (_countUpSeconds ~/ 60);
    }
    
    // Capture session data before resetting state
    final sessionName = _sessionName.isNotEmpty ? _sessionName : 'Untitled';
    final tag = _customTag ?? _selectedTag;
    final distracted = _distracted;
    final completedAt = DateTime.now();
    
    // Stop ambient playback and notifications
    _stopAmbientPlayback();
    _abortTimer?.cancel();
    _notifManager?.stop();
    
    // Reset state
    setState(() {
      _isCountingDown = false;
      _isPaused = false;
      _sessionStart = null;
      _countUpTimer?.cancel();
      _countUpSeconds = 0;
    });
    
    // Show summary dialog (which handles saving)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SessionSummaryDialog(
        sessionName: sessionName,
        tag: tag,
        durationMinutes: duration,
        distracted: distracted,
        completedAt: completedAt,
      ),
    );
  }

  void _abortSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text(
          'Abort Session?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to abort this session? It will not be saved.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Abort',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() {
        _isCountingDown = false;
        _isPaused = false;
        _sessionStart = null;
        _aborted = true;
        _countUpTimer?.cancel();
        _countUpSeconds = 0;
      });
      _stopAmbientPlayback();
      _abortTimer?.cancel();
      _notifManager?.stop();
    }
  }

  Future<void> _saveSession({
    required int durationMinutes,
    required int plannedMinutes,
  }) async {
    if (_aborted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _sessionStart == null) return;
    final endTime = DateTime.now();
    String tagToSave = _customTag ?? _selectedTag;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('sessions')
        .add({
          'sessionName': _sessionName,
          'startTime': _sessionStart,
          'endTime': endTime,
          'duration': durationMinutes,
          'planned': plannedMinutes,
          'tag': tagToSave,
          'ambient': _ambientSound,
          'distracted': _distracted,
          'aborted': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

    // Calculate and update focusScore in user's root document for leaderboard
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('sessions')
          .orderBy('endTime', descending: true)
          .limit(10)
          .get();
      final allSessions = snap.docs.map((doc) => doc.data()).toList();
      num _extractDuration(dynamic v) {
        if (v == null) return 0;
        if (v is num) return v;
        if (v is String) return num.tryParse(v) ?? 0;
        return 0;
      }

      final sessions = allSessions.where((data) {
        final dur = _extractDuration(data['duration']);
        final aborted = data['aborted'] == true;
        return dur >= 2 && !aborted;
      }).toList();
      // Diagnostic logs
      // ignore: avoid_print
      print(
        'home_screen: recomputing focusScore for ${user.uid}, totalSessions=${allSessions.length}, usable=${sessions.length}',
      );
      // print full session docs to inspect keys and types
      // ignore: avoid_print
      print('home_screen: all session docs: $allSessions');
      // ignore: avoid_print
      print(
        'home_screen: durations=${sessions.map((s) => s['duration']).toList()}',
      );
      double score = 0.0;
      double totalWeight = 0.0;
      final weights = [0.4, 0.25, 0.15, 0.12, 0.08];
      for (int i = 0; i < sessions.length && i < weights.length; i++) {
        final dur = _extractDuration(sessions[i]['duration']);
        score += dur * weights[i];
        totalWeight += weights[i];
      }
      if (sessions.length > weights.length) {
        for (int i = weights.length; i < sessions.length; i++) {
          final dur = _extractDuration(sessions[i]['duration']);
          score += dur * 0.05;
          totalWeight += 0.05;
        }
      }
      double focusScore = totalWeight > 0 ? score / totalWeight : 0.0;
      // ignore: avoid_print
      print('home_screen: computed focusScore=$focusScore for ${user.uid}');
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'focusScore': double.parse(focusScore.toStringAsFixed(2)),
          'lastUpdatedFocusAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        // ignore: avoid_print
        print('home_screen: failed to set focusScore: $e');
        // try transaction fallback
        try {
          await FirebaseFirestore.instance.runTransaction((tx) async {
            final docRef = FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid);
            final snapshot = await tx.get(docRef);
            final existing = snapshot.exists ? snapshot.data() ?? {} : {};
            final merged = {
              ...existing,
              'focusScore': double.parse(focusScore.toStringAsFixed(2)),
              'lastUpdatedFocusAt': FieldValue.serverTimestamp(),
            };
            tx.set(docRef, merged);
          });
        } catch (e, st) {
          // ignore: avoid_print
          print('home_screen: transaction fallback failed: $e\n$st');
        }
      }
    } catch (e, st) {
      // ignore: avoid_print
      print('home_screen: error recomputing focusScore: $e\n$st');
    }
  }

  void _toggleAmbient(bool value) async {
    setState(() => _ambientSound = value);
    if (value) {
      // start playback using selected sound if available, otherwise fallback to bundled asset
      await _startAmbientPlayback();
    } else {
      await _stopAmbientPlayback();
    }
  }

  Future<File> _localFileForId(
    String id,
    String? downloadUrl,
    String? storagePath,
  ) async {
    final dir = await getApplicationDocumentsDirectory();
    String ext = 'mp3';
    if (downloadUrl is String && downloadUrl.contains('.'))
      ext = downloadUrl.split('.').last;
    else if (storagePath is String && storagePath.contains('.'))
      ext = storagePath.split('.').last;
    return File('${dir.path}${Platform.pathSeparator}$id.$ext');
  }

  Future<String?> _getDownloadUrlFromStorage(String storagePath) async {
    // Firebase Storage is not used in this app (to avoid billing requirements).
    // Sounds should include a public `downloadUrl` field in Firestore (e.g. Cloudinary
    // secure_url). If you still have a storagePath stored, migrate those docs to
    // include `downloadUrl` or host the file at a public URL.
    // Return null to indicate no URL could be resolved.
    return null;
  }

  Future<void> _startAmbientPlayback() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      String? selectedId;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        selectedId = userDoc.data()?['selectedSoundId'];
      }

      if (selectedId == null) {
        // No bundled asset available any more. Prompt user to pick a sound in Sounds.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No ambient sound selected. Open Sounds to add one.'),
          ),
        );
        return;
      }

      final soundDoc = await FirebaseFirestore.instance
          .collection('sounds')
          .doc(selectedId)
          .get();
      if (!soundDoc.exists) {
        // If the referenced sound doc no longer exists, prompt the user to reselect a sound.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Selected ambient sound not found — open Sounds to choose another.',
            ),
          ),
        );
        return;
      }
      final data = soundDoc.data()!;
      final downloadUrl = data['downloadUrl'];
      final storagePath = data['storagePath'];

      final localFile = await _localFileForId(
        selectedId,
        downloadUrl,
        storagePath,
      );
      if (await localFile.exists()) {
        await _audioPlayer.setReleaseMode(ReleaseMode.loop);
        await _audioPlayer.play(DeviceFileSource(localFile.path));
        return;
      }

      String? url = downloadUrl;
      if (url == null && storagePath != null) {
        url = await _getDownloadUrlFromStorage(storagePath);
      }
      if (url == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No download URL for selected ambient sound'),
          ),
        );
        return;
      }

      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(UrlSource(url));
    } catch (e) {
      // ignore: avoid_print
      print('home_screen: ambient playback failed: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ambient playback failed')));
    }
  }

  Future<void> _stopAmbientPlayback() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  Future<void> _toggleDnd(bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final granted = await DndHelper.isAccessGranted();
      if (!granted) {
        // Ask user to grant access. We open the DND settings screen (system-level),
        // but also offer to open the app info page where users can enable notification policy if needed.
        messenger.showSnackBar(
          SnackBar(
            content: const Text(
              'Please grant Do Not Disturb access in system settings',
            ),
            action: SnackBarAction(
              label: 'App info',
              onPressed: () async {
                await DndHelper.openAppSettings();
              },
            ),
          ),
        );
        await DndHelper.openSettings();
        return;
      }
      if (value) {
        await DndHelper.enableDnd();
        setState(() => _dndEnabled = true);
        messenger.showSnackBar(
          const SnackBar(content: Text('Do Not Disturb enabled')),
        );
      } else {
        await DndHelper.disableDnd();
        setState(() => _dndEnabled = false);
        messenger.showSnackBar(
          const SnackBar(content: Text('Do Not Disturb disabled')),
        );
      }
    } catch (e) {
      // If native plugin handlers haven't been compiled into the running app, MissingPluginException is thrown.
      // Provide a helpful message to the developer/user to do a full rebuild/install.
      // ignore: avoid_print
      print('home_screen: DND toggle error: $e');
      if (e is MissingPluginException) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'DND native handler unavailable — stop and rebuild the app (flutter run) to enable DND functionality',
            ),
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to toggle Do Not Disturb')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalSeconds = _minutes * 60;
    final canStart =
        _sessionName.trim().isNotEmpty &&
        (_focusMode == 1 || _minutes != 0);
    final focusScoreAsync = ref.watch(focusScoreProvider);
    final stretchAsync = ref.watch(stretchSessionProvider);
    // Set dials reactively to stretch value. If we're currently showing the
    // countdown selector (not counting) and the user hasn't manually changed
    // the dials, force-apply the adaptive default. This ensures the
    // count-up -> countdown transition is handled even if it bypassed the
    // segmented-control onTap path.
    stretchAsync.when(
      data: (stretch) {
        if (_focusMode == 0 && !_isCountingDown && !_userManuallyChangedDials) {
          _setDialsFromStretch(stretch, force: true);
        } else {
          _setDialsFromStretch(stretch);
        }
      },
      loading: () {},
      error: (e, _) {},
    );
    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppDrawer(),
      appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16, top: 8),
              child: GestureDetector(
                onTap: () => GoRouter.of(context).push('/profile'),
                onLongPress: () => GoRouter.of(context).push('/settings'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Focus score',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    focusScoreAsync.when(
                      data: (score) => Text(
                        score.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      loading: () => const SizedBox(
                        width: 24,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      error: (e, _) => const Text(
                        '-',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      body: Padding(
        padding: const EdgeInsets.all(46.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
              // Segmented selector (choose countdown or count-up) — only show before session starts
              if (!_isCountingDown) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 2,
                      ),
                      child: Row(
                        children: [
                          _SegmentedIconButton(
                            icon: Icons.hourglass_bottom,
                            selected: _focusMode == 0,
                            onTap: () async {
                              if (_focusMode == 0) return;
                              // switch to countdown mode
                              setState(() => _focusMode = 0);
                              // Reapply adaptive default only when it makes sense
                              // (we last set dials programmatically or we've never
                              // applied the stretch). This avoids overriding a
                              // user's manual adjustments.
                              // Decide whether to reapply adaptive default.
                              // Reapply only if the user hasn't manually changed the
                              // dials since we left countdown. We detect that by
                              // (a) an explicit manual-change flag, or (b) a
                              // snapshot taken when switching to count-up — if the
                              // current dials still match the snapshot, the user
                              // didn't change them while on count-up.
                              final bool unchangedSinceSnapshot =
                                  _preCountUpMinutes == null ||
                                      (_minutes == _preCountUpMinutes);
                              if (!_userManuallyChangedDials && unchangedSinceSnapshot) {
                                final av = ref.read(stretchSessionProvider);
                                if (av is AsyncData<int>) {
                                  _setDialsFromStretch(av.value, force: true);
                                  // clear snapshot after applying
                                  _preCountUpMinutes = null;
                                } else {
                                  try {
                                    final stretch = await ref.read(stretchSessionProvider.future);
                                    _setDialsFromStretch(stretch, force: true);
                                    // clear snapshot after applying
                                    _preCountUpMinutes = null;
                                  } catch (_) {
                                    // ignore failures to fetch stretch
                                  }
                                }
                              }
                            },
                            size: 32,
                          ),
                          Container(
                            width: 1,
                            height: 24,
                            color: Colors.grey[800],
                          ),
                          _SegmentedIconButton(
                            icon: Icons.all_inclusive,
                            selected: _focusMode == 1,
                            onTap: () {
                              if (_focusMode == 1) return;
                              // snapshot current dials so we can tell later if the
                              // user changed them while on count-up. We treat the
                              // snapshot itself as not a manual change.
                              _preCountUpMinutes = _minutes;
                              _userManuallyChangedDials = false;
                              setState(() => _focusMode = 1);
                            },
                            size: 32,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 260,
                    height: 260,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer circle
                        Container(
                          width: 260,
                          height: 260,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF121212),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                        ),
                        // Stretch tooltip — show only when countdown mode is selected and not currently counting
                        if (_focusMode == 0 && !_isCountingDown)
                          Positioned(
                            top: 12,
                            right: 0,
                            child: Consumer(
                              builder: (context, ref, _) {
                                final stretchAsync = ref.watch(
                                  stretchSessionProvider,
                                );
                                final focusScoreAsync = ref.watch(
                                  focusScoreProvider,
                                );
                                return stretchAsync.when(
                                  data: (stretch) {
                                    return focusScoreAsync.when(
                                      data: (score) {
                    if (_focusMode != 0) return const SizedBox.shrink();
                    if (stretch > 0 &&
                      (stretch - score).abs() >= 1) {
                                          final diff = stretch - score;
                                          final sign = diff > 0 ? '+' : '';
                                          return Tooltip(
                                            message:
                                                'Adaptive stretch target based on your recent completion rate.',
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.blueGrey[900],
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                '$sign${diff.round()} min stretch',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          );
                                        }
                                        return const SizedBox.shrink();
                                      },
                                      loading: () => const SizedBox.shrink(),
                                      error: (e, _) => const SizedBox.shrink(),
                                    );
                                  },
                                  loading: () => const SizedBox.shrink(),
                                  error: (e, _) => const SizedBox.shrink(),
                                );
                              },
                            ),
                          ),
                        if (!_isCountingDown && _focusMode == 0)
                          // Minutes Picker
                          Column(
                            children: [
                              const SizedBox(height: 30), // Add top spacing to push content down
                              SizedBox(
                                width: 120,
                                height: 140, // Increased height to accommodate spacing
                                child: ListWheelScrollView.useDelegate(
                                  itemExtent: 45,
                                  diameterRatio: 1.2,
                                  physics: const FixedExtentScrollPhysics(),
                                  onSelectedItemChanged: (v) {
                                    setState(() {
                                      _minutes = _availableMinutes[v];
                                      _programmaticDialSet = false;
                                      _stretchAppliedOnce = true;
                                      _userManuallyChangedDials = true;
                                    });
                                  },
                                  childDelegate: ListWheelChildBuilderDelegate(
                                    builder: (ctx, i) {
                                      final diff = (i - _selectedMinutesIndex).abs();
                                      double opacity = 1.0;
                                      if (diff == 1)
                                        opacity = 0.25;
                                      else if (diff > 1)
                                        opacity = 0.1;
                                      return Opacity(
                                        opacity: opacity,
                                        child: Text(
                                          '${_availableMinutes[i]}',
                                          style: const TextStyle(
                                            fontSize: 40,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      );
                                    },
                                    childCount: _availableMinutes.length,
                                  ),
                                  controller: _minutesController,
                                ),
                              ),
                            ],
                          ),
                        if (!_isCountingDown && _focusMode == 1)
                          const Icon(
                            Icons.all_inclusive,
                            color: Colors.white,
                            size: 80,
                          ),
                        if (_isCountingDown)
                          TimerWidget(
                            key: _timerKey,
                            durationMinutes: _focusMode == 0
                                ? _minutes
                                : 0,
                            mode: _focusMode == 0
                                ? TimerMode.countdown
                                : TimerMode.countup,
                            onComplete: _focusMode == 0
                                ? _onCountdownComplete
                                : null,
                            showAmbientSound: true,
                            sessionName: _sessionName,
                            tag: _customTag ?? _selectedTag,
                            isPaused: _isPaused,
                            onPauseResume: (isPaused) {
                              setState(() {
                                _isPaused = isPaused;
                              });
                            },
                            onToggleAmbient: () =>
                                _toggleAmbient(_ambientSound),
                            ambientSound: _ambientSound,
                            showAmbientSoundButton:
                                false, // Hide ambient sound button since we have toggle below
                            showControlButtons:
                                false, // Hide control buttons since we'll add them separately at the bottom
                            timerKey: _timerKey,
                          ),
                        // Tag selector (smaller, translucent, closer to center in countdown)
                        Positioned(
                          bottom: _isCountingDown ? 70 : 24,
                          left: 0,
                          right: 0,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Align(
                                alignment: Alignment.center,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[850],
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: DropdownButton<String>(
                                    value: _customTag ?? _selectedTag,
                                    dropdownColor: Colors.grey[900],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                    underline: const SizedBox(),
                                    iconEnabledColor: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    isDense: true,
                                    items: [
                                      ...kPredefinedTags
                                          .where((tag) => tag != 'Other')
                                          .map(
                                            (tag) => DropdownMenuItem(
                                              value: tag,
                                              child: Text(tag),
                                            ),
                                          ),
                                      if (_customTag != null)
                                        DropdownMenuItem(
                                          value: _customTag,
                                          child: Text(_customTag!),
                                        ),
                                      DropdownMenuItem(
                                        value: 'Other',
                                        child: Text('Other'),
                                      ),
                                    ],
                                    onChanged: _isCountingDown
                                        ? null
                                        : (v) {
                                            setState(() {
                                              if (v == 'Other') {
                                                _showCustomTagInput = true;
                                                _selectedTag = 'Other';
                                              } else if (v != null &&
                                                  v != _customTag) {
                                                _selectedTag = v;
                                                _customTag = null;
                                                _showCustomTagInput = false;
                                              } else if (v == _customTag) {
                                                _selectedTag = v!;
                                                _showCustomTagInput = false;
                                              }
                                            });
                                          },
                                  ),
                                ),
                              ),
                              if (_showCustomTagInput && !_isCountingDown)
                                Align(
                                  alignment: Alignment.center,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: SizedBox(
                                      width: 160,
                                      child: TextField(
                                        autofocus: true,
                                        onSubmitted: (v) {
                                          if (v.trim().isNotEmpty) {
                                            setState(() {
                                              _customTag = v.trim();
                                              _selectedTag = _customTag!;
                                              _showCustomTagInput = false;
                                            });
                                          }
                                        },
                                        onChanged: (v) {
                                          if (v.trim().isEmpty) {
                                            setState(() {
                                              _customTag = null;
                                            });
                                          }
                                        },
                                        decoration: InputDecoration(
                                          hintText: 'Enter custom tag',
                                          hintStyle: const TextStyle(
                                            color: Colors.white54,
                                          ),
                                          filled: true,
                                          fillColor: Colors.grey[900],
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            borderSide: BorderSide.none,
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                vertical: 10,
                                                horizontal: 12,
                                              ),
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
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
              ),

              // Session name input (below timer when counting down)
              if (_isCountingDown) ...[
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: TextField(
                    enabled: false, // Disabled during session
                    controller: TextEditingController(text: _sessionName),
                    decoration: InputDecoration(
                      hintText: 'Session name',
                      hintStyle: const TextStyle(color: Color(0xFFE0E0E0), fontStyle: FontStyle.italic),
                      border: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 16,
                      ),
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.music_note, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Switch(
                      value: _ambientSound,
                      onChanged: (v) => _toggleAmbient(v),
                      activeColor: Colors.grey,
                      trackOutlineColor: MaterialStateProperty.all(
                        Colors.transparent,
                      ),
                      trackColor: MaterialStateProperty.all(Colors.white24),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.do_not_disturb_on, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Switch(
                      value: _dndEnabled,
                      onChanged: (v) => _toggleDnd(v),
                      activeColor: Colors.grey,
                      trackOutlineColor: MaterialStateProperty.all(
                        Colors.transparent,
                      ),
                      trackColor: MaterialStateProperty.all(Colors.white24),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // End Session button
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Center(
                    child: GestureDetector(
                      onTap: _showEndSessionPreview,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
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
                          style: TextStyle(
                            color: Color(0xFFFF5C5C),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              // Session name input (below timer when not counting down)
              if (!_isCountingDown) ...[
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: TextField(
                    enabled: !_isCountingDown,
                    onChanged: (v) => setState(() => _sessionName = v),
                    decoration: InputDecoration(
                      hintText: 'session name',
                      hintStyle: const TextStyle(color: Color(0xFF666666), fontStyle: FontStyle.italic),
                      border: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 16,
                      ),
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: GestureDetector(
                    onTap: canStart ? _startFlow : null,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: kAccentGradient,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Start Flow',
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        )
    );
  }

  String _formatCountUp(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
} // end of _HomeScreenState

class _SegmentedIconButton extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final double size;
  const _SegmentedIconButton({
    required this.icon,
    required this.selected,
    required this.onTap,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: selected ? Colors.grey[800] : Colors.transparent,
          borderRadius: BorderRadius.circular(size / 2),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.6),
      ),
    );
  }
}
