import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'planner_model.dart';

class DayView extends StatelessWidget {
  final DateTime selectedDate;
  final List<ScheduledSession> sessions;
  final Function(ScheduledSession) onTapSession;
  final VoidCallback onDateTap;

  const DayView({
    Key? key,
    required this.selectedDate,
    required this.sessions,
    required this.onTapSession,
    required this.onDateTap,
  }) : super(key: key);

  List<ScheduledSession> _getSessionsForDate(DateTime date) {
    return sessions.where((session) {
      final sessionDate = session.startAt;
      return sessionDate.year == date.year &&
          sessionDate.month == date.month &&
          sessionDate.day == date.day;
    }).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  @override
  Widget build(BuildContext context) {
    final daySessions = _getSessionsForDate(selectedDate);
    
    return Column(
      children: [
        // Date selector header
        _buildDateHeader(context),
        const Divider(height: 1),
        // Hourly timeline
        Expanded(
          child: _buildHourlyTimeline(context, daySessions),
        ),
      ],
    );
  }

  Widget _buildDateHeader(BuildContext context) {
    final isToday = DateTime.now().year == selectedDate.year &&
        DateTime.now().month == selectedDate.month &&
        DateTime.now().day == selectedDate.day;

    return InkWell(
      onTap: onDateTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEEE').format(selectedDate),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('MMM d').format(selectedDate),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isToday ? Colors.blue : Colors.white,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.calendar_today, color: Colors.white70, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHourlyTimeline(BuildContext context, List<ScheduledSession> daySessions) {
    return ListView.builder(
      itemCount: 24, // 24 hours
      itemBuilder: (context, index) {
        final hour = index;
        final hourSessions = _getSessionsInHour(daySessions, hour);

        return _buildHourBlock(context, hour, hourSessions);
      },
    );
  }

  List<ScheduledSession> _getSessionsInHour(List<ScheduledSession> sessions, int hour) {
    return sessions.where((session) {
      final startHour = session.startAt.hour;
      final totalMinutes = session.items.fold(0, (sum, item) => sum + item.durationMinutes);
      final endTime = session.startAt.add(Duration(minutes: totalMinutes));
      final endHour = endTime.hour + (endTime.minute > 0 ? 1 : 0);

      return startHour <= hour && hour < endHour;
    }).toList();
  }

  Widget _buildHourBlock(BuildContext context, int hour, List<ScheduledSession> hourSessions) {
    final hourLabel = hour == 0
        ? '12 AM'
        : hour < 12
            ? '$hour AM'
            : hour == 12
                ? '12 PM'
                : '${hour - 12} PM';

    return Container(
      height: 80,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time label
          SizedBox(
            width: 60,
            child: Padding(
              padding: const EdgeInsets.only(top: 4, left: 8),
              child: Text(
                hourLabel,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
          // Session blocks
          Expanded(
            child: Stack(
              children: hourSessions.map((session) {
                return _buildSessionBlock(context, session, hour);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionBlock(BuildContext context, ScheduledSession session, int currentHour) {
    final startMinute = session.startAt.hour == currentHour ? session.startAt.minute : 0;
    final totalMinutes = session.items.fold(0, (sum, item) => sum + item.durationMinutes);
    final endTime = session.startAt.add(Duration(minutes: totalMinutes));
    
    // Calculate how much of this hour the session occupies
    final endMinute = endTime.hour == currentHour 
        ? endTime.minute 
        : (endTime.hour > currentHour ? 60 : 0);
    
    final durationInThisHour = endMinute - startMinute;
    final topOffset = (startMinute / 60) * 80;
    final height = (durationInThisHour / 60) * 80;

    return Positioned(
      top: topOffset,
      left: 0,
      right: 0,
      height: height.clamp(10, 80),
      child: GestureDetector(
        onTap: () => onTapSession(session),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _getColorForTag(session.tag),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            session.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Color _getColorForTag(String tag) {
    final colors = {
      'Work': const Color(0xFFFF6B6B),
      'Study': const Color(0xFF4ECDC4),
      'Exercise': const Color(0xFF95E1D3),
      'Personal': const Color(0xFFF38181),
      'Other': const Color(0xFFAA96DA),
    };
    return colors[tag] ?? Colors.orange;
  }
}
