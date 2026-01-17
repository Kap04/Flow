import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'session_provider.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_blocking_screen.dart';

class InSessionScreen extends ConsumerStatefulWidget {
  const InSessionScreen({super.key});

  @override
  ConsumerState<InSessionScreen> createState() => _InSessionScreenState();
}

class _InSessionScreenState extends ConsumerState<InSessionScreen> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    // Listen for session state changes so we can show the summary when a
    // running session transitions to not-running (covers both automatic
    // completion and manual stop triggered elsewhere).
    ref.listen<SessionState?>(sessionProvider, (previous, next) {
      final wasRunning = previous?.running == true;
      final isNowRunning = next?.running == true;
      if (wasRunning && !isNowRunning) {
        // Session stopped -> show summary overlay
        // Use addPostFrameCallback to ensure we have a valid context for dialogs
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showSummary();
        });
      }
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      ref.read(sessionProvider.notifier).tick();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = ref.read(sessionProvider);
    if (session != null && session.running && !session.distracted) {
      if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
        ref.read(sessionProvider.notifier).markDistracted();
      }
    }
  }

  void _pauseOrResume() {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    if (session.paused) {
      ref.read(sessionProvider.notifier).resume();
    } else {
      ref.read(sessionProvider.notifier).pause();
    }
  }

  void _endSession() {
    // End session; the listener added in initState will detect the transition
    // from running -> not running and present the summary dialog.
    ref.read(sessionProvider.notifier).endSession();
  }

  void _showSummary() async {
    // Show a minimal summary card after the session ends. When the user
    // taps Done we save the session and return to the previous screen.
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => SimpleSessionSummaryDialog(),
    );
    ref.read(sessionProvider.notifier).reset();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final minutes = (session.secondsLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (session.secondsLeft % 60).toString().padLeft(2, '0');
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$minutes:$seconds', style: const TextStyle(fontSize: 48, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(height: 16),
              Text(session.tag, style: const TextStyle(fontSize: 16, color: Colors.white)),
              const SizedBox(height: 24),
              if (session.ambient)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.music_note, color: Color(0xFF1E88E5)),
                    SizedBox(width: 8),
                    Text('Ambient Sound', style: TextStyle(color: Color(0xFF1E88E5))),
                  ],
                ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(session.paused ? Icons.play_arrow : Icons.pause, color: session.paused ? const Color(0xFF1E88E5) : Colors.white, size: 36),
                    onPressed: _pauseOrResume,
                  ),
                  const SizedBox(width: 32),
                  IconButton(
                    icon: const Icon(Icons.stop, color: Colors.white, size: 36),
                    onPressed: _endSession,
                  ),
                ],
              ),
              const SizedBox(height: 16),
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
              if (session.distracted)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text('Distracted detected', style: TextStyle(color: Colors.redAccent)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SessionSummaryModal extends ConsumerStatefulWidget {
  @override
  ConsumerState<SessionSummaryModal> createState() => _SessionSummaryModalState();
}

class _SessionSummaryModalState extends ConsumerState<SessionSummaryModal> {
  String _mood = 'happy';
  final _notesController = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _saveSession() async {
    setState(() { _saving = true; _error = null; });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');
      final session = ref.read(sessionProvider);
      if (session == null) throw Exception('No session');
      final duration = ((session.endTime ?? DateTime.now()).difference(session.startTime ?? DateTime.now()).inSeconds / 60).round();
      await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('sessions').add({
        'startTime': session.startTime,
        'endTime': session.endTime ?? DateTime.now(),
        'duration': duration,
        'sessionName': session.sessionName,
        'tag': session.tag,
        'mood': _mood,
        'notes': _notesController.text.trim(),
        'distracted': session.distracted,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Recompute and update focusScore on the user's root document so leaderboard stays current
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('sessions')
            .orderBy('endTime', descending: true)
            .limit(10)
            .get();
  final allSessions = snap.docs.map((d) => d.data()).toList();
        num _extractDuration(dynamic v) {
          if (v == null) return 0;
          if (v is num) return v;
          if (v is String) return num.tryParse(v) ?? 0;
          return 0;
        }
        final sessions = allSessions.where((data) {
          final dur = _extractDuration(data['duration']);
          final distracted = data['distracted'] == true;
          return dur >= 2 && !distracted;
        }).toList();
  // Diagnostic logging
  // ignore: avoid_print
  print('Recomputing focusScore for ${user.uid}: total sessions=${allSessions.length}, usable=${sessions.length}');
  // print full session docs to inspect keys and types
  // ignore: avoid_print
  print('All session docs: $allSessions');
  // list durations
  // ignore: avoid_print
  print('Durations: ${sessions.map((s) => s['duration']).toList()}');
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
        print('Computed focusScore=$focusScore for ${user.uid}');
        // Try a simple set first
        try {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'focusScore': double.parse(focusScore.toStringAsFixed(2)),
            'lastUpdatedFocusAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (e) {
          // ignore: avoid_print
          print('Simple set failed, trying transaction: $e');
          // fallback to transaction
          await FirebaseFirestore.instance.runTransaction((tx) async {
            final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
            final snapshot = await tx.get(docRef);
            final existing = snapshot.exists ? snapshot.data() ?? {} : {};
            final merged = {...existing, 'focusScore': double.parse(focusScore.toStringAsFixed(2)), 'lastUpdatedFocusAt': FieldValue.serverTimestamp()};
            tx.set(docRef, merged);
          });
        }
      } catch (e, st) {
        // non-fatal: don't block session save on score update
        // ignore: avoid_print
        print('Failed to update focusScore (outer): $e\n$st');
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black87,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_mood == 'happy' ? Icons.emoji_emotions : _mood == 'neutral' ? Icons.sentiment_neutral : Icons.sentiment_dissatisfied, color: const Color(0xFF1E88E5), size: 48),
            const SizedBox(height: 16),
            Text('Session Complete!', style: const TextStyle(fontSize: 20, color: Colors.white)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Text('😊', style: TextStyle(fontSize: 28)),
                  onPressed: () => setState(() => _mood = 'happy'),
                  color: _mood == 'happy' ? const Color(0xFF1E88E5) : Colors.white,
                ),
                IconButton(
                  icon: const Text('😐', style: TextStyle(fontSize: 28)),
                  onPressed: () => setState(() => _mood = 'neutral'),
                  color: _mood == 'neutral' ? const Color(0xFF1E88E5) : Colors.white,
                ),
                IconButton(
                  icon: const Text('😫', style: TextStyle(fontSize: 28)),
                  onPressed: () => setState(() => _mood = 'sad'),
                  color: _mood == 'sad' ? const Color(0xFF1E88E5) : Colors.white,
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                hintText: 'Notes (optional)',
                hintStyle: TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Color(0xFF121212),
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(color: Colors.white),
              maxLines: 1,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveSession,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E88E5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _saving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Save', style: TextStyle(fontSize: 18, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 

// Minimal summary dialog used after a pomodoro timer completes.
class SimpleSessionSummaryDialog extends ConsumerStatefulWidget {
  const SimpleSessionSummaryDialog({Key? key}) : super(key: key);

  @override
  ConsumerState<SimpleSessionSummaryDialog> createState() => _SimpleSessionSummaryDialogState();
}

class _SimpleSessionSummaryDialogState extends ConsumerState<SimpleSessionSummaryDialog> {
  bool _saving = false;
  String? _error;

  Future<void> _done() async {
    setState(() { _saving = true; _error = null; });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');
      final session = ref.read(sessionProvider);
      if (session == null) throw Exception('No session');
      final duration = ((session.endTime ?? DateTime.now()).difference(session.startTime ?? DateTime.now()).inSeconds / 60).round();
      await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('sessions').add({
        'startTime': session.startTime,
        'endTime': session.endTime ?? DateTime.now(),
        'duration': duration,
        'sessionName': session.sessionName,
        'tag': session.tag,
        'mood': 'auto',
        'notes': '',
        'distracted': session.distracted,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // light-weight focus score update (best-effort)
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('sessions')
            .orderBy('endTime', descending: true)
            .limit(10)
            .get();
        final all = snap.docs.map((d) => d.data()).toList();
        int usable = 0; double total = 0.0;
        for (final s in all) {
          final dur = (s['duration'] ?? 0) as num;
          final distracted = s['distracted'] == true;
          if (dur >= 2 && !distracted) {
            usable++; total += dur.toDouble();
          }
        }
        final focusScore = usable > 0 ? (total / usable) : 0.0;
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({'focusScore': double.parse(focusScore.toStringAsFixed(2))}, SetOptions(merge: true));
      } catch (_) {}
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final name = session?.tag ?? 'Session';
    final durationMinutes = session != null ? (((session.endTime ?? DateTime.now()).difference(session.startTime ?? DateTime.now()).inSeconds) / 60).round() : 0;
    final completedAt = session?.endTime ?? DateTime.now();
    final focusScore = session != null ? (session.distracted ? 0.0 : (durationMinutes.toDouble())) : 0.0;

    return Dialog(
      backgroundColor: Colors.black87,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.schedule, color: Colors.white54, size: 18),
              const SizedBox(width: 8),
              Text('$durationMinutes minutes', style: const TextStyle(color: Colors.white70)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.bolt, color: Color(0xFF1E88E5), size: 18),
              const SizedBox(width: 8),
              Text('Focus score: ${focusScore.toStringAsFixed(1)}', style: const TextStyle(color: Colors.white70)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.access_time, color: Colors.white54, size: 18),
              const SizedBox(width: 8),
              Text('Completed at ${TimeOfDay.fromDateTime(completedAt).format(context)}', style: const TextStyle(color: Colors.white70)),
            ]),
            if (_error != null) Padding(padding: const EdgeInsets.only(top:8.0), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _done,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E88E5)),
                child: _saving ? const SizedBox(height:16,width:16,child:CircularProgressIndicator(color:Colors.white,strokeWidth:2)) : const Text('Done', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}