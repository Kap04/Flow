import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_drawer.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Please log in to view your history.',
            style: TextStyle(color: Colors.white70, fontSize: 18),
          ),
        ),
      );
    }

    final sessionsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('sessions');

    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('History', style: TextStyle(color: Colors.white)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: sessionsRef.orderBy('endTime', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'No sessions yet\nStart your first focus session!',
                style: TextStyle(color: Colors.white70, fontSize: 18),
                textAlign: TextAlign.center,
              ),
            );
          }

          final sessions = snapshot.data!.docs;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sessions.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('Recent Sessions', style: TextStyle(color: Colors.white, fontSize: 18)),
                );
              }

              final doc = sessions[index - 1];
              final data = doc.data() as Map<String, dynamic>;
              final start = (data['startTime'] as Timestamp?)?.toDate();
              final tag = data['tag'] ?? '';
              final duration = data['duration'] ?? 0;

              return Card(
                color: const Color(0xFF121212),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  title: Text('$tag  •  $duration min', style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    start != null ? start.toLocal().toString().split(" ")[0] : '',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

