import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
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
            leading: const Icon(Icons.timer, color: Colors.lightBlueAccent),
            title: const Text('Individual Timer', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              GoRouter.of(context).go('/home');
            },
          ),
          ListTile(
            leading: const Icon(Icons.directions_run, color: Colors.amber),
            title: const Text('Sprints', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              GoRouter.of(context).go('/sprints');
            },
          ),
          ListTile(
            leading: const Icon(Icons.person, color: Colors.grey),
            title: const Text('Profile', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              GoRouter.of(context).go('/profile');
            },
          ),
          ListTile(
            leading: const Icon(Icons.emoji_events, color: Colors.orangeAccent),
            title: const Text('Leaderboard', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              GoRouter.of(context).go('/leaderboard');
            },
          ),
          ListTile(
            leading: const Icon(Icons.music_note, color: Colors.greenAccent),
            title: const Text('Music / Sounds', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              GoRouter.of(context).go('/sounds');
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
    );
  }
}
