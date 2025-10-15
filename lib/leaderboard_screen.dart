import 'dart:math' as math;
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
    // Compute trend for a user by comparing total session minutes in the last 7 days
    // vs the previous 7-day window. Returns 1 (up), -1 (down), or 0 (flat/no-data).
    Future<int> _computeTrend(String uid) async {
      try {
        final now = DateTime.now();
        final since14 = now.subtract(const Duration(days: 14));
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('sessions')
            .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since14))
            .get();
        int last7 = 0;
        int prev7 = 0;
        for (final d in snap.docs) {
          final s = d.data();
          final ts = (s['createdAt'] as Timestamp?)?.toDate() ?? (s['startTime'] as Timestamp?)?.toDate();
          final dur = (s['duration'] as num?)?.toInt() ?? 0;
          if (ts == null) continue;
          if (ts.isAfter(now.subtract(const Duration(days: 7)))) {
            last7 += dur;
          } else {
            prev7 += dur;
          }
        }
        if (last7 > prev7) return 1;
        if (last7 < prev7) return -1;
        return 0;
      } catch (_) {
        return 0;
      }
    }
    // Helper to render avatar with subtle rank flair for top 3
    Widget _rankAvatar(int rank, String? photoUrl) {
      // muted metallic colors
      Color? ringColor;
      double ringWidth = 3.0;
      if (rank == 1) {
        ringColor = const Color(0xFFB8860B); // muted gold/bronze tone
      } else if (rank == 2) {
        ringColor = const Color(0xFF9EA7AD); // silver tone
      } else if (rank == 3) {
        ringColor = const Color(0xFFB36B3A); // bronze tone
      }

      final avatar = CircleAvatar(
        radius: 20,
        backgroundColor: Colors.grey[800],
  backgroundImage: (photoUrl != null && photoUrl.trim().isNotEmpty) ? NetworkImage(photoUrl.trim()) : null,
        child: (photoUrl == null || photoUrl.isEmpty) ? const Icon(Icons.person, color: Colors.white54) : null,
      );

      if (ringColor != null) {
        // show subtle ring by drawing a slightly larger circular container with border
        return Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // soft glow using boxShadow and a thin border to simulate metallic ring
            boxShadow: [BoxShadow(color: ringColor.withOpacity(0.18), blurRadius: 8, spreadRadius: 1)],
            border: Border.all(color: ringColor.withOpacity(0.85), width: ringWidth),
          ),
          child: avatar,
        );
      }

      return avatar;
    }

    // Helper to render trend marker; expects `trend` field in user doc (1 = up, -1 = down)
    Widget _trendMarker(int trend) {
      if (trend > 0) {
        // NE (north-east) arrow — rotate positively to point up-right
        return Transform.rotate(
          angle: math.pi / 4, // 45° -> NE
          child: const Icon(Icons.arrow_upward, size: 14, color: Color(0xFF4CAF50)),
        );
      }
      if (trend < 0) {
        // SE (south-east) arrow — rotate negatively to point down-right
        return Transform.rotate(
          angle: -math.pi / 4, // -45° -> SE
          child: const Icon(Icons.arrow_downward, size: 14, color: Color(0xFFEF5350)),
        );
      }
      return const SizedBox.shrink();
    }
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
              final photoUrl = data['photoURL'] as String?;
              final storedTrend = data.containsKey('trend') ? (data['trend'] ?? 0) as int : null;
              final rank = i + 1;
              final isTop3 = rank <= 3;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  // base background for rows: very dark for non-current users
                  color: isCurrent ? Colors.grey[900] : const Color(0xFF050505),
                  // keep a gradient for current user but make it solid (no fade)
                  gradient: isCurrent
                      ? const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [Color(0x3000BCD4), Color(0x3000BCD4)],
                        )
                      : null,
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${i + 1}', style: TextStyle(color: isCurrent ? Colors.white : Colors.white70, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      _rankAvatar(i + 1, photoUrl),
                    ],
                  ),
                  title: Text(displayName, style: TextStyle(color: isCurrent ? Colors.white : Colors.white70, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$focusScore', style: TextStyle(color: isCurrent ? Colors.cyanAccent : Colors.white, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          if (storedTrend != null)
                            _trendMarker(storedTrend)
                          else
                            FutureBuilder<int>(
                              future: _computeTrend(data['uid'] as String? ?? ''),
                              builder: (context, snapTrend) {
                                final t = snapTrend.data ?? 0;
                                return _trendMarker(t);
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Intentionally not showing a 'You' label — the row highlight is used instead.
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
