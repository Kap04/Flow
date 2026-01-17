import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

// REPLACE this with your Formspree form endpoint
const String kFormspreeEndpoint = 'https://formspree.io/f/mzzjypgq';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () {
            if (GoRouter.of(context).canPop()) {
              GoRouter.of(context).pop();
            } else {
              GoRouter.of(context).go('/home');
            }
          },
        ),
        title: const Text('Settings', style: TextStyle(fontSize: 24, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ListTile(
            leading: const Icon(Icons.feedback, color: Colors.white70),
            title: const Text('Send feedback', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Rate the app and send suggestions', style: TextStyle(color: Colors.white54)),
            onTap: () async {
              // show feedback dialog (simple form)
              await showDialog<void>(
                context: context,
                builder: (ctx) {
                  int rating = 0;
                  final TextEditingController _fbController = TextEditingController();
                  bool submitting = false;
                  Future<void> submit() async {
                    if (rating <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a rating')));
                      return;
                    }
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    String email = '';
                    if (uid != null) {
                      try {
                        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
                        email = (doc.data() ?? {})['email'] ?? '';
                      } catch (_) {}
                    }
                    final payload = {'email': email, 'uid': uid ?? '', 'rating': rating.toString(), 'feedback': _fbController.text.trim()};
                    try {
                      final res = await http.post(Uri.parse(kFormspreeEndpoint), headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload));
                      if (res.statusCode >= 200 && res.statusCode < 300) {
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks — feedback sent')));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to send feedback')));
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to send feedback')));
                    }
                  }
                  return StatefulBuilder(builder: (context, setState) {
                    return AlertDialog(
                      backgroundColor: Colors.black,
                      title: const Text('Send feedback', style: TextStyle(color: Colors.white)),
                      content: SingleChildScrollView(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Align(alignment: Alignment.centerLeft, child: Text('How many stars?', style: TextStyle(color: Colors.white70))),
                          const SizedBox(height: 8),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) {
                            final idx = i + 1;
                            return IconButton(onPressed: () => setState(() => rating = idx), icon: Icon(rating >= idx ? Icons.star : Icons.star_border, color: Colors.amber));
                          })),
                          const SizedBox(height: 8),
                          TextField(controller: _fbController, maxLines: 4, decoration: const InputDecoration(hintText: 'Any suggestions or thoughts?', hintStyle: TextStyle(color: Colors.white54), filled: true, fillColor: Color(0xFF121212)), style: const TextStyle(color: Colors.white)),
                        ]),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel', style: TextStyle(color: Colors.white))),
                        TextButton(onPressed: submitting ? null : () async { setState(() => submitting = true); await submit(); setState(() => submitting = false); }, child: const Text('Send', style: TextStyle(color: Colors.blueAccent))),
                      ],
                    );
                  });
                },
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Log out', style: TextStyle(color: Colors.white)),
            onTap: () async {
              final shouldSignOut = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: Colors.black,
                  title: const Text('Sign out?', style: TextStyle(color: Colors.white)),
                  content: const Text('Are you sure you want to sign out?', style: TextStyle(color: Colors.white70)),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel', style: TextStyle(color: Colors.white))),
                    TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Sign out', style: TextStyle(color: Colors.redAccent))),
                  ],
                ),
              );
              if (shouldSignOut != true) return;
              try { await FirebaseAuth.instance.signOut(); try { final g = GoogleSignIn(); if (await g.isSignedIn()) await g.signOut(); } catch (_) {} } catch (_) {}
              GoRouter.of(context).go('/auth');
            },
          ),
        ],
      ),
    );
  }
}

final _formulaProvider = StateProvider<String>((ref) => 'weighted');
final _lookbackProvider = StateProvider<int>((ref) => 5);
final _stretchProvider = StateProvider<String>((ref) => 'adaptive');