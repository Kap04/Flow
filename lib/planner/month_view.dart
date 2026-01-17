import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'planner_model.dart';

class MonthView extends StatefulWidget {
  final DateTime selectedMonth;
  final List<ScheduledSession> sessions;
  final Function(DateTime) onDaySelected;
  final Function(ScheduledSession) onTapSession;

  const MonthView({
    Key? key,
    required this.selectedMonth,
    required this.sessions,
    required this.onDaySelected,
    required this.onTapSession,
  }) : super(key: key);

  @override
  State<MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends State<MonthView> {
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.selectedMonth;
  }

  List<ScheduledSession> _getSessionsForDay(DateTime day) {
    return widget.sessions.where((session) {
      final sessionDate = session.startAt;
      return sessionDate.year == day.year &&
          sessionDate.month == day.month &&
          sessionDate.day == day.day;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Calendar
        TableCalendar(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: widget.selectedMonth,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          calendarFormat: CalendarFormat.month,
          startingDayOfWeek: StartingDayOfWeek.monday,
          headerStyle: HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            leftChevronIcon: const Icon(Icons.chevron_left, color: Colors.white),
            rightChevronIcon: const Icon(Icons.chevron_right, color: Colors.white),
          ),
          calendarStyle: CalendarStyle(
            defaultTextStyle: const TextStyle(color: Colors.white),
            weekendTextStyle: const TextStyle(color: Colors.white70),
            todayDecoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            selectedDecoration: const BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
            ),
            markerDecoration: const BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
            ),
            outsideTextStyle: const TextStyle(color: Colors.white24),
          ),
          daysOfWeekStyle: const DaysOfWeekStyle(
            weekdayStyle: TextStyle(color: Colors.white70),
            weekendStyle: TextStyle(color: Colors.white54),
          ),
          eventLoader: (day) {
            return _getSessionsForDay(day);
          },
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
            });
            widget.onDaySelected(selectedDay);
          },
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, date, events) {
              if (events.isEmpty) return null;
              
              return Positioned(
                bottom: 2,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: events.take(3).map((event) {
                    final session = event as ScheduledSession;
                    return Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: _getColorForTag(session.tag),
                        shape: BoxShape.circle,
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        // Selected day sessions
        if (_selectedDay != null) ...[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  DateFormat('EEEE, MMM d').format(_selectedDay!),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildDaySessionsList(_selectedDay!),
          ),
        ],
      ],
    );
  }

  Widget _buildDaySessionsList(DateTime day) {
    final daySessions = _getSessionsForDay(day);
    
    if (daySessions.isEmpty) {
      return const Center(
        child: Text(
          'No triggers for this day',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: daySessions.length,
      itemBuilder: (context, index) {
        final session = daySessions[index];
        final startTime = DateFormat('h:mm a').format(session.startAt);
        final totalMinutes = session.items.fold(0, (sum, item) => sum + item.durationMinutes);
        final endTime = DateFormat('h:mm a').format(
          session.startAt.add(Duration(minutes: totalMinutes)),
        );

        return Card(
          color: Colors.white.withOpacity(0.05),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 4,
              color: _getColorForTag(session.tag),
            ),
            title: Text(
              session.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              '$startTime - $endTime',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getColorForTag(session.tag).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                session.tag,
                style: TextStyle(
                  color: _getColorForTag(session.tag),
                  fontSize: 12,
                ),
              ),
            ),
            onTap: () => widget.onTapSession(session),
          ),
        );
      },
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
