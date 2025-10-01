import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'session_provider.dart';
import 'app_drawer.dart';
import 'package:go_router/go_router.dart';

// Time range selector for analytics
enum TimeRange { today, week, month, all }

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ValueNotifier<TimeRange> range = ValueNotifier(TimeRange.week);
    final user = FirebaseAuth.instance.currentUser;
    final focusScoreAsync = ref.watch(focusScoreProvider);
    final completionRateAsync = ref.watch(completionRateProvider);
    if (user == null) {
      return const Center(
        child: Text('Please log in to view your analytics.', style: TextStyle(color: Colors.white70, fontSize: 18)),
      );
    }
    final sessionsRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('sessions');
    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Analytics', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh analytics',
            onPressed: () async {
              // show an immediate snack
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Refreshing analytics...'), duration: Duration(seconds: 1)));
              try {
                // force recompute of focus score and dependent providers
                await ref.refresh(focusScoreProvider.future);
                // also refresh completion rate and stretch providers to ensure KPI update
                await ref.refresh(completionRateProvider.future);
                await ref.refresh(stretchSessionProvider.future);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Analytics refreshed'), duration: Duration(seconds: 1)));
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
              }
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<TimeRange>(
        valueListenable: range,
        builder: (context, selectedRange, _) {
          return StreamBuilder<QuerySnapshot>(
            stream: sessionsRef.snapshots(),
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
              } else {
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
                    if (endTime != null && endTime.isAfter(DateTime.now().subtract(const Duration(days: 7)))) {
                      deepFocusFails++;
                    }
                  }
                  if (endTime != null) {
                    final day = DateTime(endTime.year, endTime.month, endTime.day);
                    focusPerDay[day] = (focusPerDay[day] ?? 0) + duration;
                    if (lastDate == null || lastDate.difference(day).inDays == 1) {
                      streak++;
                      lastDate = day;
                    }
                    if (duration > longestSession) {
                      longestSession = duration;
                      longestSessionDate = endTime;
                    }
                  }
                }
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

                // --- UI: KPI Row, Range Selector, Analytics ---
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- KPI Row ---
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      child: Row(
                        children: [
                          _KpiCard(
                            title: 'Focus Score',
                            value: focusScoreAsync.when(
                              data: (score) => score.toStringAsFixed(1),
                              loading: () => '...',
                              error: (e, _) => '-',
                            ),
                            tooltip: 'Weighted average of your last few sessions (excludes aborted/outliers).',
                          ),
                          _KpiCard(
                            title: 'Total Focus',
                            value: totalMinutes > 0 ? '$totalMinutes min' : '-',
                            tooltip: 'Total minutes focused in selected range.',
                          ),
                          _KpiCard(
                            title: 'Streak',
                            value: streak > 0 ? '$streak' : '-',
                            tooltip: 'Consecutive days with at least one session.',
                          ),
                        ],
                      ),
                    ),
                    // --- Time Range Selector (moved down) ---
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 8, right: 8, bottom: 0),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _RangeButton(label: 'Today', selected: selectedRange == TimeRange.today, onTap: () => range.value = TimeRange.today),
                            _RangeButton(label: '7d', selected: selectedRange == TimeRange.week, onTap: () => range.value = TimeRange.week),
                            _RangeButton(label: '30d', selected: selectedRange == TimeRange.month, onTap: () => range.value = TimeRange.month),
                            _RangeButton(label: 'All', selected: selectedRange == TimeRange.all, onTap: () => range.value = TimeRange.all),
                          ],
                        ),
                      ),
                    ),
                    // --- Analytics Content ---
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
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
                          // --- Tag Breakdown (show all tags ever used) ---
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
                                  ...{
                                    ...sessions.map((doc) => (doc.data() as Map<String, dynamic>)['tag'] ?? 'Other'),
                                    ...tagMinutes.keys
                                  }.map((tag) {
                                    final highlightTag = sortedTags.isNotEmpty ? sortedTags.first.key : null;
                                    return Row(
                                      children: [
                                        Container(
                                          width: 12,
                                          height: 12,
                                          margin: const EdgeInsets.only(right: 8),
                                          decoration: BoxDecoration(
                                            color: tag == highlightTag ? const Color(0xFF1E88E5) : Colors.white24,
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                        ),
                                        Text(
                                          '$tag: ${tagMinutes[tag] ?? 0} min',
                                          style: TextStyle(
                                            color: tag == highlightTag ? const Color(0xFF1E88E5) : Colors.white70,
                                            fontWeight: tag == highlightTag ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
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
                            final duration = data['duration'] ?? 0;
                            return Card(
                              color: const Color(0xFF121212),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              child: ListTile(
                                title: Text('$tag  •  $duration min', style: const TextStyle(color: Colors.white)),
                                subtitle: Text(
                                  start != null ? start.toLocal().toString().split(" ")[0] : '',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                );
              }
            },
          );
        },
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

// Helper for time range selector button
class _RangeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RangeButton({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 32),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          backgroundColor: selected ? const Color(0xFF1E88E5) : Colors.transparent,
          foregroundColor: selected ? Colors.white : Colors.white70,
          side: BorderSide(color: selected ? const Color(0xFF1E88E5) : Colors.white24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }
}

// Helper for KPI card
class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String tooltip;
  const _KpiCard({required this.title, required this.value, required this.tooltip});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Tooltip(
        message: tooltip,
        child: Card(
          color: const Color(0xFF121212),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            width: 100,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value, style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(title, style: const TextStyle(fontSize: 13, color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}