import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'session_provider.dart';
import 'in_session_screen.dart';
import 'history_screen.dart';

const List<String> kPredefinedTags = ['Study', 'Work', 'Design', 'Other'];

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _sessionLength = 25;
  String _selectedTag = kPredefinedTags[0];
  bool _ambientSound = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sessionLength = prefs.getInt('sessionLength') ?? 25;
      _selectedTag = prefs.getString('selectedTag') ?? kPredefinedTags[0];
      _ambientSound = prefs.getBool('ambientSound') ?? false;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sessionLength', _sessionLength);
    await prefs.setString('selectedTag', _selectedTag);
    await prefs.setBool('ambientSound', _ambientSound);
  }

  void _startFlow() {
    _savePrefs();
    ref.read(sessionProvider.notifier).start(
      duration: _sessionLength,
      tag: _selectedTag,
      ambient: _ambientSound,
    );
    GoRouter.of(context).push('/in-session');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flow', style: TextStyle(fontSize: 24, color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart, color: Color(0xFF1E88E5)),
            onPressed: () => GoRouter.of(context).go('/history'),
            tooltip: 'History & Stats',
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Color(0xFF1E88E5)),
            onPressed: () => GoRouter.of(context).go('/settings'),
            tooltip: 'Settings',
          ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Center(
              child: SizedBox(
                width: 120,
                height: 80,
                child: Image.asset('assets/flow.png'),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Session Length', style: TextStyle(color: Colors.white, fontSize: 16)),
                const SizedBox(width: 16),
                DropdownButton<int>(
                  value: _sessionLength,
                  dropdownColor: const Color(0xFF121212),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  items: List.generate(12, (i) => 5 + i * 5)
                      .map((min) => DropdownMenuItem(
                            value: min,
                            child: Text('$min min'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _sessionLength = v);
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Tag', style: TextStyle(color: Colors.white, fontSize: 16)),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _selectedTag,
                  dropdownColor: const Color(0xFF121212),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  items: kPredefinedTags
                      .map((tag) => DropdownMenuItem(
                            value: tag,
                            child: Text(tag),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedTag = v);
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Ambient Sound', style: TextStyle(color: Colors.white, fontSize: 16)),
                const SizedBox(width: 12),
                Switch(
                  value: _ambientSound,
                  onChanged: (v) => setState(() => _ambientSound = v),
                  activeColor: const Color(0xFF1E88E5),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _startFlow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E88E5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Start Flow', style: TextStyle(fontSize: 18, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 