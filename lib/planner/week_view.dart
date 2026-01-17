import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'planner_model.dart';

class WeekView extends StatelessWidget {
  final DateTime selectedWeek;
  final List<ScheduledSession> sessions;
  final Function(ScheduledSession) onTapSession;

  const WeekView({
    Key? key,
    required this.selectedWeek,
    required this.sessions,
    required this.onTapSession,
  }) : super(key: key);

  DateTime _getWeekStart(DateTime date) {
    final dayOfWeek = date.weekday;
    return date.subtract(Duration(days: dayOfWeek - 1));
  }

  List<DateTime> _getWeekDays() {
    final start = _getWeekStart(selectedWeek);
    return List.generate(7, (index) => start.add(Duration(days: index)));
  }

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
    final weekDays = _getWeekDays();
    
    return Column(
      children: [
        // Week header with day names
        _buildWeekHeader(weekDays),
        const Divider(height: 1),
        // Scrollable hourly timeline
        Expanded(
          child: _buildWeekTimeline(weekDays),
        ),
      ],
    );
  }

  Widget _buildWeekHeader(List<DateTime> weekDays) {
    final now = DateTime.now();
    
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 60), // Space for time labels
          ...weekDays.map((day) {
            final isToday = day.year == now.year &&
                day.month == now.month &&
                day.day == now.day;
            
            return Expanded(
              child: Column(
                children: [
                  Text(
                    DateFormat('E').format(day),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isToday ? Colors.blue : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isToday ? Colors.white : Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildWeekTimeline(List<DateTime> weekDays) {
    return ListView.builder(
      itemCount: 24, // 24 hours
      itemBuilder: (context, hourIndex) {
        return _buildHourRow(hourIndex, weekDays);
      },
    );
  }

  Widget _buildHourRow(int hour, List<DateTime> weekDays) {
    final hourLabel = hour == 0
        ? '12 AM'
        : hour < 12
            ? '$hour AM'
            : hour == 12
                ? '12 PM'
                : '${hour - 12} PM';

    return Container(
      height: 60,
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
          // Day columns
          ...weekDays.map((day) {
            final daySessions = _getSessionsForDate(day);
            final hourSessions = _getSessionsInHour(daySessions, hour);
            
            return Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: Colors.white.withOpacity(0.05)),
                  ),
                ),
                child: Stack(
                  children: hourSessions.map((session) {
                    return _buildSessionBlock(session, hour);
                  }).toList(),
                ),
              ),
            );
          }).toList(),
        ],
      ),
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

  Widget _buildSessionBlock(ScheduledSession session, int currentHour) {
    final startMinute = session.startAt.hour == currentHour ? session.startAt.minute : 0;
    final totalMinutes = session.items.fold(0, (sum, item) => sum + item.durationMinutes);
    final endTime = session.startAt.add(Duration(minutes: totalMinutes));
    
    final endMinute = endTime.hour == currentHour 
        ? endTime.minute 
        : (endTime.hour > currentHour ? 60 : 0);
    
    final durationInThisHour = endMinute - startMinute;
    final topOffset = (startMinute / 60) * 60;
    final height = (durationInThisHour / 60) * 60;

    return Positioned(
      top: topOffset,
      left: 0,
      right: 0,
      height: height.clamp(10, 60),
      child: GestureDetector(
        onTap: () => onTapSession(session),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _getColorForTag(session.tag),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            session.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
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
