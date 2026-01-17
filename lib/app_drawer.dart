import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'session_provider.dart';
import 'app_blocking_screen.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      backgroundColor: Colors.black,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Live profile header: displays avatar + display name and reacts to changes in Firestore
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseAuth.instance.currentUser == null
                ? const Stream<DocumentSnapshot>.empty()
                : FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).snapshots(),
            builder: (context, snap) {
              final user = FirebaseAuth.instance.currentUser;
              String displayName = user?.displayName ?? 'Profile';
              String? photoUrl = user?.photoURL;
              if (snap.hasData && snap.data!.data() != null) {
                final data = snap.data!.data() as Map<String, dynamic>;
                if ((data['displayName'] as String?)?.trim().isNotEmpty ?? false) displayName = data['displayName'] as String;
                if ((data['photoURL'] as String?)?.trim().isNotEmpty ?? false) photoUrl = data['photoURL'] as String?;
              }
              return DrawerHeader(
                decoration: const BoxDecoration(color: Colors.black),
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    GoRouter.of(context).push('/profile');
                  },
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.grey[800],
                        backgroundImage: (photoUrl != null && photoUrl.trim().isNotEmpty) ? CachedNetworkImageProvider(photoUrl.trim()) : null,
                        child: (photoUrl == null || photoUrl.trim().isEmpty) ? const Icon(Icons.person, color: Colors.white) : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            // Show live focus score fetched from the shared provider
                            Builder(builder: (ctx) {
                              final focusAsync = ref.watch(focusScoreProvider);
                              return focusAsync.when(
                                data: (v) => Text('Focus score: ${v.toStringAsFixed(1)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                loading: () => Row(children: const [SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 8), Text('Focus score', style: TextStyle(color: Colors.white70, fontSize: 12))]),
                                error: (_, __) => const Text('Focus score: -', style: TextStyle(color: Colors.white70, fontSize: 12)),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.timer, color: Colors.lightBlueAccent),
            title: const Text('Pomodoro', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              GoRouter.of(context).go('/home');
            },
          ),
          ListTile(
            leading: const Icon(Icons.view_module, color: Colors.amber),
            title: const Text('Time Blocks', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              GoRouter.of(context).push('/sprints');
            },
          ),
          ListTile(
            leading: const Icon(Icons.schedule, color: Colors.blue),
            title: const Text('Flow Triggers', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              GoRouter.of(context).push('/planner');
            },
          ),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.red),
            title: const Text('Block Apps', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => AppBlockingScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.person, color: Colors.grey),
            title: const Text('Profile', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              GoRouter.of(context).push('/profile');
            },
          ),
          ListTile(
            leading: const Icon(Icons.emoji_events, color: Colors.orangeAccent),
            title: const Text('Leaderboard', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              GoRouter.of(context).push('/leaderboard');
            },
          ),
          ListTile(
            leading: const Icon(Icons.music_note, color: Colors.greenAccent),
            title: const Text('Music / Sounds', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              GoRouter.of(context).push('/sounds');
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.grey),
            title: const Text('Settings', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              GoRouter.of(context).push('/settings');
            },
          ),
        ],
      ),
    );
  }
}
