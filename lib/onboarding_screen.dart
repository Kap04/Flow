import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'gradients.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  void _goToAuth(BuildContext context) {
    GoRouter.of(context).go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: () => _goToAuth(context),
                  child: const Text('Skip', style: TextStyle(color: Colors.white)),
                ),
              ),
              const Spacer(),
              Center(
                child: Image.asset(
                  'assets/flow.png',
                  width: 120,
                  height: 80,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Welcome to Flow',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: Colors.white),
              ),
              const SizedBox(height: 16),
              const Text(
                'What is flow state?\nA focused, distraction-free mindset for deep work and creativity.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.white70),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => _goToAuth(context),
                child: Container(
                  width: double.infinity,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: kAccentGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text('Next', style: TextStyle(fontSize: 18, color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 