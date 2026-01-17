import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Pomodoro timer session summary dialog
class SessionSummaryDialog extends ConsumerStatefulWidget {
  final String sessionName;
  final String tag;
  final int durationMinutes;
  final bool distracted;
  final DateTime completedAt;

  const SessionSummaryDialog({
    Key? key,
    required this.sessionName,
    required this.tag,
    required this.durationMinutes,
    required this.distracted,
    required this.completedAt,
  }) : super(key: key);

  @override
  ConsumerState<SessionSummaryDialog> createState() => _SessionSummaryDialogState();
}

class _SessionSummaryDialogState extends ConsumerState<SessionSummaryDialog> {
  bool _processing = false;
  String? _error;

  Future<void> _saveSession() async {
    setState(() { _processing = true; _error = null; });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');
      
      await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('sessions').add({
        'startTime': widget.completedAt.subtract(Duration(minutes: widget.durationMinutes)),
        'endTime': widget.completedAt,
        'duration': widget.durationMinutes,
        'sessionName': widget.sessionName,
        'tag': widget.tag,
        'mood': 'auto',
        'notes': '',
        'distracted': widget.distracted,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      // Update focus score - simple average of all sessions
      try {
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
      } catch (_) {}
      
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
    final focusScore = widget.durationMinutes;
    final timeOfDay = TimeOfDay.fromDateTime(widget.completedAt);
    final timeString = timeOfDay.format(context);

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
            
            // Session Name (inline)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Session Name', style: TextStyle(color: Colors.white70, fontSize: 16)),
                Flexible(
                  child: Text(
                    widget.sessionName,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Duration (digit blue, regular size)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Duration', style: TextStyle(color: Colors.white70, fontSize: 16)),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '${widget.durationMinutes}',
                        style: const TextStyle(color: Color(0xFF1E88E5), fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const TextSpan(text: ' min', style: TextStyle(color: Colors.white70, fontSize: 16)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Completed at
            Text('Completed at $timeString', style: const TextStyle(color: Colors.grey, fontSize: 14)),

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
                    onPressed: _processing ? null : _saveSession,
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
