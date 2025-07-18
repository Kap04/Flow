import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('Not signed in', style: TextStyle(color: Colors.white))),
      );
    }
    final sessionsRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('sessions').orderBy('startTime', descending: true);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('History & Stats', style: TextStyle(fontSize: 24, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: sessionsRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No sessions yet', style: TextStyle(color: Colors.white70)));
          }
          final sessions = snapshot.data!.docs;
          // Simple stats
          int totalMinutes = 0;
          int streak = 0;
          Map<String, int> tagCounts = {};
          DateTime? lastDate;
          for (final doc in sessions) {
            final data = doc.data() as Map<String, dynamic>;
            totalMinutes += (data['duration'] ?? 0) as int;
            final tag = data['tag'] ?? 'Other';
            tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
            final endTime = (data['endTime'] as Timestamp?)?.toDate();
            if (endTime != null) {
              if (lastDate == null || endTime.difference(lastDate).inDays == 1) {
                streak++;
                lastDate = endTime;
              }
            }
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: const Color(0xFF121212),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Focus Time: $totalMinutes min', style: const TextStyle(color: Colors.white)),
                      Text('Session Count: ${sessions.length}', style: const TextStyle(color: Colors.white)),
                      Text('Streak: $streak', style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 8),
                      Text('Tag Breakdown:', style: const TextStyle(color: Colors.white)),
                      ...tagCounts.entries.map((e) => Text('${e.key}: ${e.value}', style: const TextStyle(color: Colors.white70))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Recent Sessions', style: TextStyle(color: Colors.white, fontSize: 18)),
              const SizedBox(height: 8),
              ...sessions.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final start = (data['startTime'] as Timestamp?)?.toDate();
                final end = (data['endTime'] as Timestamp?)?.toDate();
                final tag = data['tag'] ?? '';
                final mood = data['mood'] ?? '';
                final duration = data['duration'] ?? 0;
                return Card(
                  color: const Color(0xFF121212),
                  child: ListTile(
                    title: Text('$tag  •  $duration min', style: const TextStyle(color: Colors.white)),
                    subtitle: Text('${start?.toLocal().toString().split(" ")[0] ?? ''}  ${mood.isNotEmpty ? '• $mood' : ''}', style: const TextStyle(color: Colors.white70)),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
} 