import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'planner/planner_model.dart';
import 'sprint_timer_screen.dart';
import 'gradients.dart';

class SprintPreviewScreen extends ConsumerStatefulWidget {
  final ScheduledSession scheduledSession;
  final String? preCreatedSprintId;

  const SprintPreviewScreen({
    super.key,
    required this.scheduledSession,
    this.preCreatedSprintId,
  });

  @override
  ConsumerState<SprintPreviewScreen> createState() => _SprintPreviewScreenState();
}

class _SprintPreviewScreenState extends ConsumerState<SprintPreviewScreen> {
  bool _isStarting = false;

  Future<void> _startSprint() async {
    if (_isStarting) return;
    setState(() => _isStarting = true);

    try {
      // Navigate to the actual sprint timer screen
      final goalName = widget.scheduledSession.title;
      final sprintName = widget.scheduledSession.items.isNotEmpty 
          ? widget.scheduledSession.items[0].label ?? widget.scheduledSession.title 
          : widget.scheduledSession.title;
      final durationMinutes = widget.scheduledSession.items.isNotEmpty 
          ? widget.scheduledSession.items[0].durationMinutes 
          : 25;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => SprintTimerScreen(
            goalName: goalName,
            sprintName: sprintName,
            durationMinutes: durationMinutes,
            sprintIndex: 0,
            scheduledSession: widget.scheduledSession,
            preCreatedSprintId: widget.preCreatedSprintId,
          ),
        ),
      );
    } catch (e) {
      print('Error starting sprint: $e');
      setState(() => _isStarting = false);
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final hours = dateTime.hour.toString().padLeft(2, '0');
    final minutes = dateTime.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.scheduledSession;
    
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        title: const Text('Session Ready'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Session Title
            Text(
              session.title,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            
            // Scheduled time
            Text(
              'Scheduled for ${_formatDateTime(session.startAt)}',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 32),

            // Session Items
            Text(
              'Session Plan:',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: ListView.builder(
                itemCount: session.items.length,
                itemBuilder: (context, index) {
                  final item = session.items[index];
                  final isBreak = index < session.items.length - 1 && 
                                 (item.breakAfterMinutes ?? 0) > 0;
                  
                  return Column(
                    children: [
                      // Timer Item
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: kAccentGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.label ?? 'Sprint ${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${item.durationMinutes} minutes',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.timer,
                              color: Colors.white70,
                            ),
                          ],
                        ),
                      ),
                      
                      // Break between sessions (if not last item)
                      if (isBreak)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.coffee,
                                color: Colors.orange,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Break: ${item.breakAfterMinutes ?? 0} minutes',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            // Start Button
            const SizedBox(height: 32),
            Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                gradient: kAccentGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ElevatedButton(
                onPressed: _isStarting ? null : _startSprint,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isStarting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Start Time Blocks',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}