import 'package:flutter/material.dart';
import 'app_drawer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Leaderboard', style: TextStyle(color: Colors.white)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No users found.', style: TextStyle(color: Colors.white70)));
          }
          final users = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
          users.sort((a, b) {
            final aScore = (a.data()['focusScore'] ?? 0) as num;
            final bScore = (b.data()['focusScore'] ?? 0) as num;
            return bScore.compareTo(aScore);
          });
          final currentIndex = users.indexWhere((d) => d.data()['uid'] == currentUid);
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final doc = users[i];
              final data = doc.data();
              final displayName = (data['displayName'] ?? data['email'] ?? 'User') as String;
              final focusScore = (data['focusScore'] ?? 0) as num;
              final isCurrent = data['uid'] == currentUid;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isCurrent ? Colors.blue.withOpacity(0.15) : Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isCurrent ? Colors.blue : Colors.grey[800],
                    child: Text('${i + 1}', style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(displayName, style: TextStyle(color: isCurrent ? Colors.white : Colors.white70, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$focusScore', style: TextStyle(color: isCurrent ? Colors.cyanAccent : Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      if (isCurrent) const Text('You', style: TextStyle(color: Colors.white54, fontSize: 12))
                    ],
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
