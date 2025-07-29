import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'session_provider.dart';
import 'in_session_screen.dart';
import 'history_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:circular_countdown_timer/circular_countdown_timer.dart';
import 'gradients.dart';
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

const List<String> kPredefinedTags = ['Study', 'Work', 'Design', 'Other'];

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _hours = 0;
  int _minutes = 25;
  String _selectedTag = kPredefinedTags[0];
  bool _ambientSound = false;
  bool _isCountingDown = false;
  bool _isPaused = false;
  late CountDownController _countDownController;
  DateTime? _sessionStart;
  bool _distracted = false;
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
  late FixedExtentScrollController _hoursController;
  late FixedExtentScrollController _minutesController;
  bool _programmaticDialSet = false;
  bool _stretchAppliedOnce = false;

  @override
  void initState() {
    super.initState();
    _countDownController = CountDownController();
    _hoursController = FixedExtentScrollController(initialItem: _hours);
    _minutesController = FixedExtentScrollController(initialItem: _minutes);
    _loadPrefs();
  }

  @override
  void dispose() {
    _countUpTimer?.cancel();
    _audioPlayer.dispose();
    _abortTimer?.cancel();
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedTag = prefs.getString('selectedTag') ?? kPredefinedTags[0];
      _ambientSound = prefs.getBool('ambientSound') ?? false;
    });
  }

  void _setDialsFromStretch(int stretch) {
    // If stretch changed, allow re-application
    if (_lastStretch != stretch) {
      _stretchAppliedOnce = false;
    }
    if (!_isCountingDown && stretch > 0 && !_stretchAppliedOnce) {
      _programmaticDialSet = true;
      setState(() {
        _hours = stretch ~/ 60;
        _minutes = stretch % 60;
        _lastStretch = stretch;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_programmaticDialSet) {
          _hoursController.jumpToItem(_hours);
          _minutesController.jumpToItem(_minutes);
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
      if (_focusMode == 1) {
        _countUpSeconds = 0;
        _countUpTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!_isPaused) {
            setState(() => _countUpSeconds++);
          }
        });
      }
      _abortTimer?.cancel();
      _abortTimer = Timer(const Duration(seconds: 61), () {
        setState(() {});
      });
    });
  }

  void _onCountdownComplete() {
    _saveSession(durationMinutes: _hours * 60 + _minutes, plannedMinutes: _hours * 60 + _minutes);
    setState(() {
      _isCountingDown = false;
      _isPaused = false;
      _sessionStart = null;
    });
    _abortTimer?.cancel();
  }

  void _stopSession() {
    int duration = 0;
    int planned = _hours * 60 + _minutes;
    if (_focusMode == 0) {
      if (_sessionStart != null) {
        duration = DateTime.now().difference(_sessionStart!).inSeconds ~/ 60;
        if (duration > planned) duration = planned;
        if (duration < 0) duration = 0;
      }
    } else {
      duration = (_countUpSeconds ~/ 60);
    }
    _saveSession(durationMinutes: duration, plannedMinutes: planned);
    setState(() {
      _isCountingDown = false;
      _isPaused = false;
      _sessionStart = null;
      _countUpTimer?.cancel();
      _countUpSeconds = 0;
    });
    _abortTimer?.cancel();
  }

  void _abortSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('Abort Session?', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to abort this session? It will not be saved.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Abort', style: TextStyle(color: Colors.redAccent)),
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
      _abortTimer?.cancel();
    }
  }

  Future<void> _saveSession({required int durationMinutes, required int plannedMinutes}) async {
    if (_aborted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _sessionStart == null) return;
    final endTime = DateTime.now();
    await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('sessions').add({
      'sessionName': _sessionName,
      'startTime': _sessionStart,
      'endTime': endTime,
      'duration': durationMinutes,
      'planned': plannedMinutes,
      'tag': _selectedTag,
      'ambient': _ambientSound,
      'distracted': _distracted,
      'aborted': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  void _toggleAmbient(bool value) async {
    setState(() => _ambientSound = value);
    if (value) {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(AssetSource('soothing-deep-noise.mp3'));
    } else {
      await _audioPlayer.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalSeconds = _hours * 3600 + _minutes * 60;
    final canStart = _sessionName.trim().isNotEmpty && (_focusMode == 1 || (_hours != 0 || _minutes != 0));
    final focusScoreAsync = ref.watch(focusScoreProvider);
    final stretchAsync = ref.watch(stretchSessionProvider);
    // Set dials reactively to stretch value
    stretchAsync.when(
      data: (stretch) => _setDialsFromStretch(stretch),
      loading: () {},
      error: (e, _) {},
    );
    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        backgroundColor: Colors.black,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Colors.black),
              child: Center(
                child: Icon(Icons.menu, color: Colors.white, size: 48),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart, color: Colors.grey),
              title: const Text('Analytics', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                GoRouter.of(context).go('/history');
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.grey),
              title: const Text('Settings', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                GoRouter.of(context).go('/settings');
              },
            ),
          ],
        ),
      ),
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
              onTap: () => GoRouter.of(context).go('/history'),
              onLongPress: () => GoRouter.of(context).go('/settings'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Focus score', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  focusScoreAsync.when(
                    data: (score) => Text(
                      score.toStringAsFixed(1),
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    loading: () => const SizedBox(width: 24, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    error: (e, _) => const Text('-', style: TextStyle(color: Colors.white)),
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
            // Segmented selector
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  child: Row(
                    children: [
                      _SegmentedIconButton(
                        icon: Icons.hourglass_bottom,
                        selected: _focusMode == 0,
                        onTap: () => setState(() => _focusMode = 0),
                        size: 32,
                      ),
                      Container(width: 1, height: 24, color: Colors.grey[800]),
                      _SegmentedIconButton(
                        icon: Icons.all_inclusive,
                        selected: _focusMode == 1,
                        onTap: () => setState(() => _focusMode = 1),
                        size: 32,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
                      // Stretch tooltip
                      if (!_isCountingDown)
                        Positioned(
                          top: 12,
                          right: 0,
                          child: Consumer(
                            builder: (context, ref, _) {
                              final stretchAsync = ref.watch(stretchSessionProvider);
                              final focusScoreAsync = ref.watch(focusScoreProvider);
                              return stretchAsync.when(
                                data: (stretch) {
                                  return focusScoreAsync.when(
                                    data: (score) {
                                      if (stretch > 0 && (stretch - score).abs() >= 1) {
                                        final diff = stretch - score;
                                        final sign = diff > 0 ? '+' : '';
                                        return Tooltip(
                                          message: 'Adaptive stretch target based on your recent completion rate.',
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.blueGrey[900],
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text('$sign${diff.round()} min stretch', style: const TextStyle(color: Colors.white, fontSize: 13)),
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
                        // Timer Picker
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 60,
                              height: 120,
                              child: ListWheelScrollView.useDelegate(
                                itemExtent: 40,
                                diameterRatio: 1.2,
                                physics: const FixedExtentScrollPhysics(),
                                onSelectedItemChanged: (v) {
                                  setState(() {
                                    _hours = v;
                                    _programmaticDialSet = false;
                                    _stretchAppliedOnce = true;
                                  });
                                },
                                childDelegate: ListWheelChildBuilderDelegate(
                                  builder: (ctx, i) {
                                    final diff = (i - _hours).abs();
                                    double opacity = 1.0;
                                    if (diff == 1) opacity = 0.2;
                                    else if (diff > 1) opacity = 0.08;
                                    return Opacity(
                                      opacity: opacity,
                                      child: Text('$i', style: const TextStyle(fontSize: 32, color: Colors.white)),
                                    );
                                  },
                                  childCount: 12, // 0-11 hours
                                ),
                                controller: _hoursController,
                              ),
                            ),
                            const Text(':', style: TextStyle(fontSize: 32, color: Colors.white70)),
                            SizedBox(
                              width: 60,
                              height: 120,
                              child: ListWheelScrollView.useDelegate(
                                itemExtent: 40,
                                diameterRatio: 1.2,
                                physics: const FixedExtentScrollPhysics(),
                                onSelectedItemChanged: (v) {
                                  setState(() {
                                    _minutes = v;
                                    _programmaticDialSet = false;
                                    _stretchAppliedOnce = true;
                                  });
                                },
                                childDelegate: ListWheelChildBuilderDelegate(
                                  builder: (ctx, i) {
                                    final diff = (i - _minutes).abs();
                                    double opacity = 1.0;
                                    if (diff == 1) opacity = 0.2;
                                    else if (diff > 1) opacity = 0.08;
                                    return Opacity(
                                      opacity: opacity,
                                      child: Text(i.toString().padLeft(2, '0'), style: const TextStyle(fontSize: 32, color: Colors.white)),
                                    );
                                  },
                                  childCount: 60,
                                ),
                                controller: _minutesController,
                              ),
                            ),
                          ],
                        ),
                      if (!_isCountingDown && _focusMode == 1)
                        const Icon(Icons.all_inclusive, color: Colors.white, size: 80),
                      if (_isCountingDown && _focusMode == 0)
                        CircularCountDownTimer(
                          duration: totalSeconds,
                          initialDuration: 0,
                          controller: _countDownController,
                          width: 240,
                          height: 240,
                          ringColor: Color(0xFF222222),
                          fillColor: Color.fromRGBO(10, 172, 223, 1),
                          backgroundColor: const Color(0xFF121212),
                          strokeWidth: 16.0,
                          strokeCap: StrokeCap.round,
                          textStyle: const TextStyle(
                            fontSize: 44.0,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          isReverse: true,
                          isReverseAnimation: true,
                          isTimerTextShown: true,
                          autoStart: true,
                          onComplete: _onCountdownComplete,
                        ),
                      if (_isCountingDown && _focusMode == 1)
                        Center(
                          child: Text(
                            _formatCountUp(_countUpSeconds),
                            style: const TextStyle(fontSize: 44, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      // Tag selector (smaller, translucent, closer to center in countdown)
                      Positioned(
                        bottom: _isCountingDown ? 70 : 24,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey[850],
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: DropdownButton<String>(
                              value: _selectedTag,
                              dropdownColor: Colors.grey[900],
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              underline: const SizedBox(),
                              iconEnabledColor: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              isDense: true,
                              items: kPredefinedTags
                                  .map((tag) => DropdownMenuItem(
                                        value: tag,
                                        child: Text(tag),
                                      ))
                                  .toList(),
                              onChanged: _isCountingDown
                                  ? null
                                  : (v) {
                                      if (v != null) setState(() => _selectedTag = v);
                                    },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Session name input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: TextField(
                enabled: !_isCountingDown,
                onChanged: (v) => setState(() => _sessionName = v),
                decoration: InputDecoration(
                  hintText: 'Session name',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.grey[900],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Ambient Sound', style: TextStyle(color: Colors.white, fontSize: 16)),
                const SizedBox(width: 12),
                Switch(
                  value: _ambientSound,
                  onChanged: (v) => _toggleAmbient(v),
                  activeColor: Colors.grey,
                  trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
                  trackColor: MaterialStateProperty.all(Colors.white24),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (!_isCountingDown)
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
                    child: const Text('Start Flow', style: TextStyle(fontSize: 18, color: Colors.white)),
                  ),
                ),
              ),
            if (_isCountingDown)
              Stack(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            if (_isPaused) {
                              if (_focusMode == 1) {
                                // resume count up
                              }
                              _countDownController.resume();
                            } else {
                              if (_focusMode == 1) {
                                // pause count up
                              }
                              _countDownController.pause();
                            }
                            _isPaused = !_isPaused;
                          });
                        },
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(_isPaused ? Icons.play_arrow : Icons.pause, color: Colors.white, size: 32),
                        ),
                      ),
                      const SizedBox(width: 32),
                      GestureDetector(
                        onTap: _stopSession,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white70,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.8),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],    
                          ),
                          child: Center(
                            child: Container(
                              width: 21,
                              height: 21,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Abort X button for first minute
                  if (_sessionStartTime != null && DateTime.now().difference(_sessionStartTime!).inSeconds < 60)
                    Positioned(
                      right: 0,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.redAccent, size: 32),
                        tooltip: 'Abort Session',
                        onPressed: _abortSession,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _formatCountUp(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _SegmentedIconButton extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final double size;
  const _SegmentedIconButton({required this.icon, required this.selected, required this.onTap, this.size = 40});

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