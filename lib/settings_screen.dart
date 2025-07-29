import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'session_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outlierThreshold = ref.watch(outlierThresholdProvider);
    final outlierEnabled = outlierThreshold > 0;
    final lookback = ref.watch(_lookbackProvider);
    final formula = ref.watch(_formulaProvider);
    final stretch = ref.watch(_stretchProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontSize: 24, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('Advanced Settings', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          // Formula type
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Formula type', style: TextStyle(color: Colors.white70)),
              Tooltip(
                message: 'How your Focus score is calculated. Weighted reacts faster, median ignores outliers.',
                child: const Icon(Icons.info_outline, color: Colors.white38, size: 18),
              ),
            ],
          ),
          DropdownButton<String>(
            value: formula,
            dropdownColor: Colors.grey[900],
            style: const TextStyle(color: Colors.white),
            items: const [
              DropdownMenuItem(value: 'weighted', child: Text('Weighted moving average')),
              DropdownMenuItem(value: 'simple', child: Text('Simple average (last N)')),
              DropdownMenuItem(value: 'median', child: Text('Median of last N')),
            ],
            onChanged: (v) => ref.read(_formulaProvider.notifier).state = v!,
          ),
          const SizedBox(height: 20),
          // Look-back window
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Look-back window (N)', style: TextStyle(color: Colors.white70)),
              Tooltip(
                message: 'How many sessions are used to calculate your Focus score.',
                child: const Icon(Icons.info_outline, color: Colors.white38, size: 18),
              ),
            ],
          ),
          Slider(
            value: lookback.toDouble(),
            min: 3,
            max: 10,
            divisions: 7,
            label: lookback.toString(),
            onChanged: (v) => ref.read(_lookbackProvider.notifier).state = v.round(),
          ),
          const SizedBox(height: 20),
          // Stretch increment
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Stretch increment', style: TextStyle(color: Colors.white70)),
              Tooltip(
                message: 'Progressively increases your challenge. Adaptive means it grows as you improve.',
                child: const Icon(Icons.info_outline, color: Colors.white38, size: 18),
              ),
            ],
          ),
          DropdownButton<String>(
            value: stretch,
            dropdownColor: Colors.grey[900],
            style: const TextStyle(color: Colors.white),
            items: const [
              DropdownMenuItem(value: 'off', child: Text('Off (0%)')),
              DropdownMenuItem(value: 'fixed', child: Text('Fixed 5%')),
              DropdownMenuItem(value: 'adaptive', child: Text('Adaptive 5–15%')),
            ],
            onChanged: (v) => ref.read(_stretchProvider.notifier).state = v!,
          ),
          const SizedBox(height: 20),
          // Outlier filter
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Outlier filter', style: TextStyle(color: Colors.white70)),
              Tooltip(
                message: 'Ignore very short or aborted sessions so mistakes don\'t hurt your stats.',
                child: const Icon(Icons.info_outline, color: Colors.white38, size: 18),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Switch(
                value: outlierEnabled,
                onChanged: (v) => ref.read(outlierThresholdProvider.notifier).state = v ? 2 : 0,
                activeColor: Colors.blue,
              ),
              if (outlierEnabled)
                Expanded(
                  child: Slider(
                    value: outlierThreshold.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: outlierThreshold.toString(),
                    onChanged: (v) => ref.read(outlierThresholdProvider.notifier).state = v.round(),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 32),
          Center(
            child: ElevatedButton(
              onPressed: () {
                ref.read(_formulaProvider.notifier).state = 'weighted';
                ref.read(_lookbackProvider.notifier).state = 5;
                ref.read(_stretchProvider.notifier).state = 'adaptive';
                ref.read(outlierThresholdProvider.notifier).state = 2;
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white10,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Reset to default'),
            ),
          ),
        ],
      ),
    );
  }
}

final _formulaProvider = StateProvider<String>((ref) => 'weighted');
final _lookbackProvider = StateProvider<int>((ref) => 5);
final _stretchProvider = StateProvider<String>((ref) => 'adaptive'); 