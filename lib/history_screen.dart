import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'session_provider.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    final focusScoreAsync = ref.watch(focusScoreProvider);
    final completionRateAsync = ref.watch(completionRateProvider);
    if (user == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('Not signed in', style: TextStyle(color: Colors.white))),
      );
    }
    final sessionsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('sessions')
        .orderBy('startTime', descending: true);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('History & Stats', style: TextStyle(fontSize: 24, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Card(
              color: const Color(0xFF121212),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Focus score', style: TextStyle(color: Colors.white54, fontSize: 14)),
                    focusScoreAsync.when(
                      data: (score) => Text(
                        score.toStringAsFixed(1),
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      loading: () => const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                      error: (e, _) => const Text('-', style: TextStyle(color: Colors.white)),
                    ),
                    const SizedBox(height: 4),
                    const Text('Weighted average of your last few sessions (excludes aborted/outliers).', style: TextStyle(color: Colors.white38, fontSize: 12)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Completion rate:', style: TextStyle(color: Colors.white54, fontSize: 14)),
                        const SizedBox(width: 8),
                        completionRateAsync.when(
                          data: (rate) => Text('${(rate * 100).toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          loading: () => const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          error: (e, _) => const Text('-', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: sessionsRef.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No sessions yet\nStart your first focus session!',
                      style: TextStyle(color: Colors.white70, fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                final sessions = snapshot.data!.docs;
                // --- Stats Calculation ---
                int totalMinutes = 0;
                int streak = 0;
                int deepFocusFails = 0;
                Map<String, int> tagMinutes = {};
                Map<DateTime, int> focusPerDay = {};
                int longestSession = 0;
                DateTime? longestSessionDate;
                int bestDayMinutes = 0;
                DateTime? bestDayDate;
                DateTime? lastDate;
                for (final doc in sessions) {
                  final data = doc.data() as Map<String, dynamic>;
                  final duration = (data['duration'] ?? 0) as int;
                  totalMinutes += duration;
                  final tag = data['tag'] ?? 'Other';
                  tagMinutes[tag] = (tagMinutes[tag] ?? 0) + duration;
                  final endTime = (data['endTime'] as Timestamp?)?.toDate();
                  final distracted = data['distracted'] == true;
                  if (distracted) {
                    // Count if in the last 7 days
                    if (endTime != null && endTime.isAfter(DateTime.now().subtract(const Duration(days: 7)))) {
                      deepFocusFails++;
                    }
                  }
                  // Streak calculation (consecutive days)
                  if (endTime != null) {
                    final day = DateTime(endTime.year, endTime.month, endTime.day);
                    focusPerDay[day] = (focusPerDay[day] ?? 0) + duration;
                    if (lastDate == null || lastDate.difference(day).inDays == 1) {
                      streak++;
                      lastDate = day;
                    }
                    // Longest session
                    if (duration > longestSession) {
                      longestSession = duration;
                      longestSessionDate = endTime;
                    }
                  }
                }
                // Best day
                focusPerDay.forEach((day, minutes) {
                  if (minutes > bestDayMinutes) {
                    bestDayMinutes = minutes;
                    bestDayDate = day;
                  }
                });

                // --- Line Chart Data (last 7 days) ---
                final now = DateTime.now();
                final last7Days = List.generate(7, (i) {
                  final d = now.subtract(Duration(days: 6 - i));
                  return DateTime(d.year, d.month, d.day);
                });
                final lineSpots = last7Days
                    .map((d) => FlSpot(
                        d.millisecondsSinceEpoch.toDouble(),
                        (focusPerDay[d] ?? 0).toDouble()))
                    .toList();

                // --- Tag Breakdown List ---
                final sortedTags = tagMinutes.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // --- Top Stats Card ---
                    Card(
                      color: const Color(0xFF121212),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _statColumn('Total\nFocus', '$totalMinutes min', accent: true),
                            _statColumn('Sessions', '${sessions.length}'),
                            _statColumn('Streak', '$streak'),
                            _statColumn(
                              'Distractions',
                              '$deepFocusFails',
                              accent: deepFocusFails > 0,
                              accentColor: Colors.redAccent,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // --- Focus Trend Line Chart ---
                    Card(
                      color: const Color(0xFF121212),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Focus Trend (Last 7 Days)', style: TextStyle(color: Colors.white, fontSize: 16)),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 180,
                              child: LineChart(
                                LineChartData(
                                  gridData: FlGridData(show: false),
                                  borderData: FlBorderData(show: false),
                                  titlesData: FlTitlesData(
                                    leftTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 32,
                                        getTitlesWidget: (value, meta) => Text(
                                          value.toInt().toString(),
                                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                                        ),
                                      ),
                                    ),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        getTitlesWidget: (value, meta) {
                                          final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 8),
                                            child: Text(
                                              '${date.month}/${date.day}',
                                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                                            ),
                                          );
                                        },
                                        interval: (last7Days[1].millisecondsSinceEpoch - last7Days[0].millisecondsSinceEpoch).toDouble(),
                                      ),
                                    ),
                                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  ),
                                  minX: last7Days.first.millisecondsSinceEpoch.toDouble(),
                                  maxX: last7Days.last.millisecondsSinceEpoch.toDouble(),
                                  minY: 0,
                                  maxY: (lineSpots.map((e) => e.y).reduce((a, b) => a > b ? a : b) + 10).clamp(30, 120),
                                  lineBarsData: [
                                    LineChartBarData(
                                      spots: lineSpots,
                                      isCurved: true,
                                      color: const Color(0xFF1E88E5),
                                      barWidth: 4,
                                      dotData: FlDotData(show: false),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // --- Highlight Cards ---
                    Row(
                      children: [
                        Expanded(
                          child: Card(
                            color: const Color(0xFF121212),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                children: [
                                  const Text('Longest Session', style: TextStyle(color: Colors.white70)),
                                  const SizedBox(height: 8),
                                  Text(
                                    longestSession > 0 ? '$longestSession min' : '-',
                                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  if (longestSessionDate != null)
                                    Text(
                                      '${longestSessionDate!.month}/${longestSessionDate!.day}',
                                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Card(
                            color: const Color(0xFF121212),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                children: [
                                  const Text('Best Day', style: TextStyle(color: Colors.white70)),
                                  const SizedBox(height: 8),
                                  Text(
                                    bestDayMinutes > 0 ? '$bestDayMinutes min' : '-',
                                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  if (bestDayDate != null)
                                    Text(
                                      '${bestDayDate!.month}/${bestDayDate!.day}',
                                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // --- Tag Breakdown ---
                    Card(
                      color: const Color(0xFF121212),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Tag Breakdown', style: TextStyle(color: Colors.white, fontSize: 16)),
                            const SizedBox(height: 8),
                            ...sortedTags.map((e) => Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: e.key == sortedTags.first.key ? const Color(0xFF1E88E5) : Colors.white24,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                Text(
                                  '${e.key}: ${e.value} min',
                                  style: TextStyle(
                                    color: e.key == sortedTags.first.key ? const Color(0xFF1E88E5) : Colors.white70,
                                    fontWeight: e.key == sortedTags.first.key ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            )),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // --- Recent Sessions List ---
                    const Text('Recent Sessions', style: TextStyle(color: Colors.white, fontSize: 18)),
                    const SizedBox(height: 8),
                    ...sessions.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final start = (data['startTime'] as Timestamp?)?.toDate();
                      final tag = data['tag'] ?? '';
                      final mood = data['mood'] ?? '';
                      final duration = data['duration'] ?? 0;
                      final distracted = data['distracted'] == true;
                      return Card(
                        color: const Color(0xFF121212),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        child: ListTile(
                          leading: distracted
                              ? const Icon(Icons.warning, color: Colors.redAccent)
                              : null,
                          title: Text('$tag  •  $duration min', style: const TextStyle(color: Colors.white)),
                          subtitle: Text(
                            '${start?.toLocal().toString().split(" ")[0] ?? ''}  ${mood.isNotEmpty ? '• $mood' : ''}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          trailing: mood == 'happy'
                              ? const Text('😊', style: TextStyle(fontSize: 20))
                              : mood == 'neutral'
                                  ? const Text('��', style: TextStyle(fontSize: 20))
                                  : mood == 'sad'
                                      ? const Text('😫', style: TextStyle(fontSize: 20))
                                      : null,
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static Widget _statColumn(String label, String value, {bool accent = false, Color? accentColor}) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: accent ? (accentColor ?? const Color(0xFF1E88E5)) : Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
} 