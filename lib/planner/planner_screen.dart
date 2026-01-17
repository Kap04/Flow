import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import '../sprint_persistence.dart';
import 'planner_model.dart';
import 'scheduled_notification_service.dart';
import 'day_view.dart';
import 'week_view.dart';
import 'month_view.dart';
import 'google_calendar_service.dart';

// Top-level class for session entry
class _SessionEntry {
  TextEditingController titleController;
  int durationMinutes;
  TextEditingController durationController;
  int? breakAfterMinutes; // Break after this session (null for last session)

  _SessionEntry({String? title, this.durationMinutes = 30, this.breakAfterMinutes})
      : titleController = TextEditingController(text: title ?? ''),
        durationController = TextEditingController(text: (durationMinutes).toString());
}

class PlannerScreen extends StatefulWidget {
  const PlannerScreen({Key? key}) : super(key: key);

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> with TickerProviderStateMixin {
  final Map<String, AnimationController> _animationControllers = {};
  final Map<String, Animation<Offset>> _slideAnimations = {};
  String? _swipedSessionId;
  
  // View state
  String _selectedView = 'Triggers'; // Triggers, Day, Week, Month
  DateTime _selectedDate = DateTime.now();
  final GoogleCalendarService _calendarService = GoogleCalendarService();
  bool _showDatePicker = false;

  @override
  void dispose() {
    for (final controller in _animationControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  AnimationController _getAnimationController(String sessionId) {
    if (!_animationControllers.containsKey(sessionId)) {
      _animationControllers[sessionId] = AnimationController(
        duration: const Duration(milliseconds: 200),
        vsync: this,
      );
      _slideAnimations[sessionId] = Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(0.15, 0), // Slide just enough to reveal button
      ).animate(CurvedAnimation(
        parent: _animationControllers[sessionId]!,
        curve: Curves.easeOut,
      ));
    }
    return _animationControllers[sessionId]!;
  }

  void _handleSwipeReveal(String sessionId) {
    setState(() {
      _swipedSessionId = sessionId;
    });
    _getAnimationController(sessionId).forward();
  }

  void _handleSwipeBack() {
    if (_swipedSessionId != null) {
      _getAnimationController(_swipedSessionId!).reverse();
      setState(() {
        _swipedSessionId = null;
      });
    }
  }

  String _formatTime(DateTime time) {
    final hour = time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  Widget _buildMiniCalendar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Month/Year header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() {
                    _selectedDate = DateTime(
                      _selectedDate.year,
                      _selectedDate.month - 1,
                    );
                  });
                },
              ),
              Text(
                DateFormat('MMMM yyyy').format(_selectedDate),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() {
                    _selectedDate = DateTime(
                      _selectedDate.year,
                      _selectedDate.month + 1,
                    );
                  });
                },
              ),
            ],
          ),
          // Calendar grid
          _buildCalendarGrid(),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDayOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
    final lastDayOfMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 0);
    final startingWeekday = firstDayOfMonth.weekday % 7;
    
    final days = <Widget>[];
    
    // Day names header
    final dayNames = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    days.addAll(dayNames.map((name) => Center(
      child: Text(name, style: const TextStyle(color: Colors.white54, fontSize: 12)),
    )));
    
    // Empty cells before first day
    for (int i = 0; i < startingWeekday; i++) {
      days.add(Container());
    }
    
    // Days of the month
    for (int day = 1; day <= lastDayOfMonth.day; day++) {
      final date = DateTime(_selectedDate.year, _selectedDate.month, day);
      final isSelected = _selectedDate.day == day;
      final isToday = DateTime.now().year == date.year &&
          DateTime.now().month == date.month &&
          DateTime.now().day == date.day;
      
      days.add(
        GestureDetector(
          onTap: () {
            setState(() {
              _selectedDate = date;
              _showDatePicker = false;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue : (isToday ? Colors.blue.withOpacity(0.3) : null),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$day',
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      );
    }
    
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: days,
    );
  }

  void _showSessionSheet(ScheduledSession session) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => PlannerEditSheet(existingSession: session),
    );
  }

  Widget _buildTriggersList(List<ScheduledSession> sessions, User user) {
    return ListView.builder(
      itemCount: sessions.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final session = sessions[index];
        final totalDuration = session.items.fold(0, (sum, item) => sum + item.durationMinutes) +
            session.items.asMap().entries.where((entry) => entry.key < session.items.length - 1).fold(0, (sum, entry) => sum + (entry.value.breakAfterMinutes ?? 5));
        
        final animationController = _getAnimationController(session.id);
        final slideAnimation = _slideAnimations[session.id]!;
        
        return GestureDetector(
          onTap: () {
            if (_swipedSessionId == session.id) {
              // If this card is swiped, slide it back
              _handleSwipeBack();
            } else if (_swipedSessionId == null) {
              // If no card is swiped, show edit sheet
              _showSessionSheet(session);
            }
          },
          onPanUpdate: (details) {
            if (_swipedSessionId == null && details.delta.dx > 0) {
              // Only allow swipe if no other card is currently swiped
              final screenWidth = MediaQuery.of(context).size.width;
              final progress = (details.localPosition.dx / screenWidth).clamp(0.0, 0.15);
              animationController.value = progress / 0.15;
            }
          },
          onPanEnd: (details) {
            if (_swipedSessionId == null) {
              if (animationController.value > 0.5) {
                // Complete the swipe
                _handleSwipeReveal(session.id);
              } else {
                // Snap back
                animationController.reverse();
              }
            }
          },
          child: Stack(
                    children: [
                      // Delete button positioned behind the card
                      Positioned(
                        left: 10,
                        top: 0,
                        bottom: 8, // Match card's bottom margin
                        child: GestureDetector(
                          onTap: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete Session'),
                                content: const Text('Are you sure you want to delete this scheduled session?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            
                            if (confirm == true) {
                              await ScheduledNotificationService.cancelSessionNotifications(session.id);
                              await PlannerService().deleteSession(user.uid, session.id);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Session deleted')),
                                );
                              }
                              _handleSwipeBack(); // Reset swipe state
                            }
                          },
                          child: Container(
                            width: 60,
                            decoration: BoxDecoration(
                              color: Colors.red[600]?.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.red[400]!.withOpacity(0.5),
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.delete_outline,
                                color: Colors.red[300],
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Sliding card
                      SlideTransition(
                        position: slideAnimation,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey[900],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[800]!, width: 1),
                          ),
                          child: Row(
                            children: [
                              Flexible(
                                flex: 3,
                                child: Text(
                                  session.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Flexible(
                                flex: 2,
            
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 16,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${totalDuration}min',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[400],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Flexible(
                                flex: 2,
                                child: Text(
                                  _formatTime(session.startAt),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Flow Triggers'),
        ),
        body: const Center(
          child: Text('Please log in to view your scheduled sessions'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            // View selector dropdown
            PopupMenuButton<String>(
              initialValue: _selectedView,
              child: Row(
                children: [
                  Text(_selectedView == 'Triggers' ? 'Flow Triggers' : '$_selectedView View'),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
              onSelected: (value) {
                setState(() {
                  _selectedView = value;
                  if (value == 'Day' || value == 'Week' || value == 'Month') {
                    _selectedDate = DateTime.now();
                  }
                });
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'Triggers', child: Text('Triggers')),
                const PopupMenuItem(value: 'Day', child: Text('Day')),
                const PopupMenuItem(value: 'Week', child: Text('Week')),
                const PopupMenuItem(value: 'Month', child: Text('Month')),
              ],
            ),
            const Spacer(),
            // Date picker button for Day view
            if (_selectedView == 'Day')
              IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: () {
                  setState(() {
                    _showDatePicker = !_showDatePicker;
                  });
                },
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Mini calendar for Day view
          if (_showDatePicker && _selectedView == 'Day')
            _buildMiniCalendar(),
          // Main content
          Expanded(
            child: GestureDetector(
              onTap: () {
                // Tap anywhere to slide back any open cards
                _handleSwipeBack();
                if (_showDatePicker) {
                  setState(() {
                    _showDatePicker = false;
                  });
                }
              },
              child: StreamBuilder<List<ScheduledSession>>(
                stream: PlannerService().getSessions(user.uid),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  final sessions = snapshot.data ?? [];

                  if (sessions.isEmpty && _selectedView == 'Triggers') {
                    return const Center(
                      child: Text('No scheduled sessions.\nTap + to create one.'),
                    );
                  }

                  // Render different views
                  switch (_selectedView) {
                    case 'Day':
                      return DayView(
                        selectedDate: _selectedDate,
                        sessions: sessions,
                        onTapSession: (session) => _showSessionSheet(session),
                        onDateTap: () {
                          setState(() {
                            _showDatePicker = !_showDatePicker;
                          });
                        },
                      );
                    case 'Week':
                      return WeekView(
                        selectedWeek: _selectedDate,
                        sessions: sessions,
                        onTapSession: (session) => _showSessionSheet(session),
                      );
                    case 'Month':
                      return MonthView(
                        selectedMonth: _selectedDate,
                        sessions: sessions,
                        onDaySelected: (day) {
                          setState(() {
                            _selectedDate = day;
                            _selectedView = 'Day';
                          });
                        },
                        onTapSession: (session) => _showSessionSheet(session),
                      );
                    case 'Triggers':
                    default:
                      return _buildTriggersList(sessions, user);
                  }
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (context) => const PlannerEditSheet(),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class PlannerEditSheet extends StatefulWidget {
  final ScheduledSession? existingSession;
  
  const PlannerEditSheet({Key? key, this.existingSession}) : super(key: key);

  @override
  State<PlannerEditSheet> createState() => _PlannerEditSheetState();
}

class _PlannerEditSheetState extends State<PlannerEditSheet> {
  final TextEditingController _titleController = TextEditingController();
  final List<_SessionEntry> _entries = [_SessionEntry(title: '', durationMinutes: 30)];
  final List<String> _availableTags = ['unset', 'study', 'work', 'read', 'rest', 'other'];
  String? _selectedTag;
  final TextEditingController _otherTagController = TextEditingController();
  int _selectedHour = 12;
  int _selectedMinute = 0;
  String _selectedPeriod = 'AM';
  TimeOfDay? _selectedTime;
  String _selectedFrequency = 'today';
  List<String> _selectedNotifications = [];
  List<String> _selectedDays = []; // For custom frequency
  final List<String> _weekDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  @override
  void initState() {
    super.initState();
    final now = TimeOfDay.now();
    _selectedHour = now.hourOfPeriod;
    _selectedMinute = now.minute;
    _selectedPeriod = now.period == DayPeriod.am ? 'AM' : 'PM';
    _selectedTime = now; // Set default to current time
    
    // Initialize with existing session data if editing
    if (widget.existingSession != null) {
      final session = widget.existingSession!;
      _titleController.text = session.title;
      _selectedTag = session.tag;
      _selectedTime = TimeOfDay.fromDateTime(session.startAt);
      _selectedHour = _selectedTime!.hourOfPeriod;
      _selectedMinute = _selectedTime!.minute;
      _selectedPeriod = _selectedTime!.period == DayPeriod.am ? 'AM' : 'PM';
      
      // Convert existing items to entries
      _entries.clear();
      for (int i = 0; i < session.items.length; i++) {
        final item = session.items[i];
        _entries.add(_SessionEntry(
          title: item.label,
          durationMinutes: item.durationMinutes,
          breakAfterMinutes: item.breakAfterMinutes,
        ));
      }
      
      // Set frequency based on recurrence
      if (session.recurrence?.type == 'daily') {
        _selectedFrequency = 'Every day';
      } else if (session.recurrence?.type == 'custom') {
        _selectedFrequency = 'custom';
        // Convert day numbers back to names
        _selectedDays = session.recurrence!.daysOfWeek!.map((dayNum) {
          switch (dayNum) {
            case 1: return 'Monday';
            case 2: return 'Tuesday';
            case 3: return 'Wednesday';
            case 4: return 'Thursday';
            case 5: return 'Friday';
            case 6: return 'Saturday';
            case 7: return 'Sunday';
            default: return 'Monday';
          }
        }).toList();
      } else {
        _selectedFrequency = 'today';
      }
      
      // Convert reminder offsets to notification strings
      _selectedNotifications = session.reminderOffsets.map((offset) {
        switch (offset) {
          case 10: return '10 minutes before';
          case 30: return '30 minutes before';
          case 60: return '1 hour before';
          default: return '10 minutes before';
        }
      }).toList();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final e in _entries) {
      e.titleController.dispose();
      e.durationController.dispose();
    }
    _otherTagController.dispose();
    super.dispose();
  }

  void _addEntry() {
    setState(() {
      // Set break duration for the previous last entry (if exists)
      if (_entries.isNotEmpty) {
        _entries.last.breakAfterMinutes ??= 5; // Default 5 minutes
      }
      _entries.add(_SessionEntry(title: '', durationMinutes: 30));
    });
  }

  void _removeEntry(int index) {
    setState(() {
      _entries[index].titleController.dispose();
      _entries.removeAt(index);
    });
  }

  Future<void> _showNotificationPicker(BuildContext context) async {
    final options = ['10 minutes before', '30 minutes before', '1 hour before'];
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final opt = options[index];
              return ListTile(
                title: Text(opt),
                onTap: () {
                  Navigator.pop(context, opt);
                },
              );
            },
          ),
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (!_selectedNotifications.contains(picked)) {
          _selectedNotifications.add(picked);
        }
      });
    }
  }

  void _pickTime(BuildContext context) async {
    await _showCustomTimePicker(context);
  }

  Future<void> _showCustomTimePicker(BuildContext context) async {
    // Ensure a valid initial index for the hour wheel (hourOfPeriod can be 0..11,
    // and our wheel shows 1..12 mapped to indices 0..11).
    final int initialHourIndex = (_selectedHour == 0) ? 11 : (_selectedHour - 1);
    final hourController = FixedExtentScrollController(initialItem: initialHourIndex);
    final minuteController = FixedExtentScrollController(initialItem: _selectedMinute.clamp(0, 59));
    final periodController = FixedExtentScrollController(initialItem: _selectedPeriod == 'AM' ? 0 : 1);

    await showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Hours
                    SizedBox(
                      width: 60,
                      height: 140,
                      child: ListWheelScrollView.useDelegate(
                        controller: hourController,
                        itemExtent: 40,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: (index) {
                          _selectedHour = index + 1;
                        },
                        childDelegate: ListWheelChildBuilderDelegate(
                          builder: (context, index) {
                            return Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 24,
                                  color: index + 1 == _selectedHour ? Colors.white : Colors.grey,
                                ),
                              ),
                            );
                          },
                          childCount: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    // Minutes
                    SizedBox(
                      width: 60,
                      height: 140,
                      child: ListWheelScrollView.useDelegate(
                        controller: minuteController,
                        itemExtent: 40,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: (index) {
                          _selectedMinute = index;
                        },
                        childDelegate: ListWheelChildBuilderDelegate(
                          builder: (context, index) {
                            return Center(
                              child: Text(
                                index.toString().padLeft(2, '0'),
                                style: TextStyle(
                                  fontSize: 24,
                                  color: index == _selectedMinute ? Colors.white : Colors.grey,
                                ),
                              ),
                            );
                          },
                          childCount: 60,
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    // AM/PM
                    SizedBox(
                      width: 60,
                      height: 140,
                      child: ListWheelScrollView.useDelegate(
                        controller: periodController,
                        itemExtent: 40,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: (index) {
                          _selectedPeriod = index == 0 ? 'AM' : 'PM';
                        },
                        childDelegate: ListWheelChildBuilderDelegate(
                          builder: (context, index) {
                            return Center(
                              child: Text(
                                index == 0 ? 'AM' : 'PM',
                                style: TextStyle(
                                  fontSize: 24,
                                  color: (index == 0 && _selectedPeriod == 'AM') || (index == 1 && _selectedPeriod == 'PM')
                                      ? Colors.white
                                      : Colors.grey,
                                ),
                              ),
                            );
                          },
                          childCount: 2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _selectedTime = TimeOfDay(
                        hour: _selectedHour % 12 + (_selectedPeriod == 'PM' ? 12 : 0),
                        minute: _selectedMinute,
                      );
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  int _notificationStringToMinutes(String notification) {
    if (notification == '10 minutes before') return 10;
    if (notification == '30 minutes before') return 30;
    if (notification == '1 hour before') return 60;
    return 10;
  }

  int _calculateTotalMinutes() {
    int total = 0;
    for (int i = 0; i < _entries.length; i++) {
      total += _entries[i].durationMinutes;
      if (i < _entries.length - 1) {
        total += _entries[i].breakAfterMinutes ?? 5;
      }
    }
    return total;
  }

  String _formatTimeWithPeriod(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<void> _saveSession() async {
    // Validate all required fields
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a session title')),
      );
      return;
    }

    if (_entries.isEmpty || _entries.any((e) => e.titleController.text.trim().isEmpty || e.durationMinutes <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one valid session with name and duration')),
      );
      return;
    }

    if (_selectedTag == null || _selectedTag!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a tag')),
      );
      return;
    }

    if (_selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a start time')),
      );
      return;
    }

    if (_selectedNotifications.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one notification')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to save sessions')),
      );
      return;
    }

    try {
      // Check and request exact alarm permission for Android 12+
      final hasPermission = await ScheduledNotificationService.checkAndRequestPermissions();
      if (!hasPermission) {
        if (mounted) {
          final shouldContinue = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Permission Required'),
              content: const Text(
                'This app needs permission to schedule exact alarms for your session notifications. '
                'Please enable "Alarms & reminders" permission in the next screen.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
          
          if (shouldContinue == true) {
            await openAppSettings();
            return;
          } else {
            return;
          }
        }
        return;
      }
      
      // Build start time from selected date and time
      final now = DateTime.now();
      DateTime startDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );
      
      // If the time is in the past, schedule for tomorrow
      if (startDateTime.isBefore(now)) {
        startDateTime = startDateTime.add(const Duration(days: 1));
        print('Selected time is in the past, scheduling for tomorrow: $startDateTime');
      } else {
        print('Scheduling for today: $startDateTime');
      }

      // Convert session entries to TimerItem list
      final items = _entries.asMap().entries.map((entry) {
        final index = entry.key;
        final sessionEntry = entry.value;
        return TimerItem(
          durationMinutes: sessionEntry.durationMinutes,
          label: sessionEntry.titleController.text.trim(),
          breakAfterMinutes: index < _entries.length - 1 ? (sessionEntry.breakAfterMinutes ?? 5) : null,
        );
      }).toList();

      // Convert notification strings to minute offsets
      final reminderOffsets = _selectedNotifications
          .map((n) => _notificationStringToMinutes(n))
          .toList();

      // Build recurrence object based on frequency
      Recurrence? recurrence;
      if (_selectedFrequency == 'Every day') {
        recurrence = Recurrence(type: 'daily');
      } else if (_selectedFrequency == 'custom' && _selectedDays.isNotEmpty) {
        // Convert day names to numbers (Monday=1, Sunday=7)
        final dayNumbers = _selectedDays.map((day) {
          switch (day) {
            case 'Monday': return 1;
            case 'Tuesday': return 2;
            case 'Wednesday': return 3;
            case 'Thursday': return 4;
            case 'Friday': return 5;
            case 'Saturday': return 6;
            case 'Sunday': return 7;
            default: return 1;
          }
        }).toList();
        recurrence = Recurrence(type: 'custom', daysOfWeek: dayNumbers);
      } else if (_selectedFrequency == 'tomorrow') {
        // For tomorrow, schedule once but for tomorrow
        startDateTime = startDateTime.add(const Duration(days: 1));
        recurrence = Recurrence(type: 'none');
      } else {
        recurrence = Recurrence(type: 'none');
      }

      // Create or update scheduled session
      final scheduledSession = ScheduledSession(
        id: widget.existingSession?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        userId: user.uid,
        title: _titleController.text.trim(),
        items: items,
        tag: _selectedTag!,
        startAt: startDateTime,
        timezone: DateTime.now().timeZoneName,
        recurrence: recurrence,
        reminderOffsets: reminderOffsets,
        enabled: true,
        createdAt: widget.existingSession?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        sprintSessionId: widget.existingSession?.sprintSessionId,
      );

      // Save to Firestore
      final service = PlannerService();
      if (widget.existingSession != null) {
        // Update existing session
        await service.updateSession(scheduledSession);
        // Cancel old notifications and schedule new ones
        await ScheduledNotificationService.cancelSessionNotifications(scheduledSession.id);
        await ScheduledNotificationService.scheduleSessionNotifications(scheduledSession);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session updated successfully!')),
          );
          Navigator.pop(context);
        }
      } else {
        // Create new session - Pre-create sprint session for instant launching
        String? sprintSessionId;
        try {
          final sprintData = {
          'scheduledSessionId': scheduledSession.id,
          'goalName': scheduledSession.title,
          'sprintName': items.isNotEmpty ? (items[0].label ?? scheduledSession.title) : scheduledSession.title,
          'durationMinutes': items.isNotEmpty ? items[0].durationMinutes : 25,
          'sprintIndex': 0,
          'status': 'scheduled', // Mark as scheduled, not active
          'items': items.map((item) => {
            'label': item.label,
            'durationMinutes': item.durationMinutes,
            'breakAfterMinutes': item.breakAfterMinutes,
          }).toList(),
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'startTime': null, // Will be set when actually started
          'endTime': null,
          'breaks': [], // Will be populated during actual sprint
          'focusScore': null,
        };

        final sprintRef = await saveSprintSessionRecord(
          userId: user.uid,
          data: sprintData,
        );
        sprintSessionId = sprintRef.id;
        print('✓ Pre-created sprint session: $sprintSessionId');
      } catch (e) {
        print('✗ Failed to pre-create sprint session: $e');
        // Continue without sprint session - will create on demand if needed
      }

      // Update scheduled session with sprint session ID
      final session = ScheduledSession(
        id: scheduledSession.id,
        userId: scheduledSession.userId,
        title: scheduledSession.title,
        items: scheduledSession.items,
        tag: scheduledSession.tag,
        startAt: scheduledSession.startAt,
        timezone: scheduledSession.timezone,
        recurrence: scheduledSession.recurrence,
        reminderOffsets: scheduledSession.reminderOffsets,
        enabled: scheduledSession.enabled,
        createdAt: scheduledSession.createdAt,
        updatedAt: scheduledSession.updatedAt,
        sprintSessionId: sprintSessionId, // Link to pre-created sprint
      );

      // Save to Firestore
      final service = PlannerService();
      await service.createSession(session);

      // Schedule notifications
      await ScheduledNotificationService.scheduleSessionNotifications(session);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session scheduled successfully!')),
        );
        Navigator.pop(context);
      }
      } // Close else block
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving session: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 16,
        left: 16,
        right: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with X button (left) and Save button (right)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
                ElevatedButton(
                  onPressed: _saveSession,
                  child: const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: 'Add Title',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey, width: 0.5),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey, width: 0.5),
                ),
              ),
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 16),

            // Tags section - horizontal scrollable chips
            SizedBox(
              height: 40,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final tag in _availableTags)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          label: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 12,
                              color: _selectedTag == tag ? Colors.white : Colors.grey[400],
                            ),
                          ),
                          selected: _selectedTag == tag,
                          onSelected: (selected) {
                            setState(() {
                              _selectedTag = selected ? tag : null;
                              if (tag != 'other') {
                                _otherTagController.clear();
                              }
                            });
                          },
                          selectedColor: Colors.blue[700],
                          backgroundColor: Colors.grey[800],
                          checkmarkColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            
            // Custom tag input when 'other' is selected
            if (_selectedTag == 'other') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _otherTagController,
                decoration: InputDecoration(
                  hintText: 'Enter custom tag',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onChanged: (val) {
                  setState(() {
                    _selectedTag = val.isEmpty ? 'other' : val;
                  });
                },
              ),
            ],
            
            const SizedBox(height: 16),

            // Session entries with break durations
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _entries.length,
              separatorBuilder: (_, index) => Column(
                children: [
                  const SizedBox(height: 4),
                  // Show break duration editor for all entries except the last one
                  if (index < _entries.length - 1) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '----- ',
                          style: TextStyle(
                            color: Colors.grey[600], 
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: TextFormField(
                            initialValue: (_entries[index].breakAfterMinutes ?? 5).toString(),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[400], fontSize: 14),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (value) {
                              final minutes = int.tryParse(value) ?? 5;
                              setState(() {
                                _entries[index].breakAfterMinutes = minutes;
                              });
                            },
                          ),
                        ),
                        Text(
                          ' min break ',
                          style: TextStyle(
                            color: Colors.grey[400], 
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '-----',
                          style: TextStyle(
                            color: Colors.grey[600], 
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
              itemBuilder: (context, index) {
                final entry = _entries[index];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: entry.titleController,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'session name',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.hourglass_bottom, size: 20),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: entry.durationController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            suffixText: 'min',
                          ),
                          onChanged: (value) {
                            final minutes = int.tryParse(value) ?? entry.durationMinutes;
                            setState(() {
                              entry.durationMinutes = minutes;
                            });
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeEntry(index),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 8),
            Center(
              child: OutlinedButton(
                onPressed: _addEntry,
                child: const Text('Add'),
              ),
            ),

            const SizedBox(height: 12),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),

            const SizedBox(height: 16),

            // Start and End time section
            Column(
              children: [
                GestureDetector(
                  onTap: () => _pickTime(context),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Starts at: ${_selectedTime != null ? _formatTimeWithPeriod(_selectedTime!) : '--:-- --'}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Ends at: ${_selectedTime != null ? _formatTimeWithPeriod(TimeOfDay.fromDateTime(DateTime(2000, 1, 1, _selectedTime!.hour, _selectedTime!.minute).add(Duration(minutes: _calculateTotalMinutes())))) : '--:-- --'}',
                      style: TextStyle(fontSize: 16, color: Colors.grey[400]),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),

            const SizedBox(height: 16),

            // Frequency selection - horizontal chips
            SizedBox(
              height: 40,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final freq in ['today', 'tomorrow', 'Every day', 'custom'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          label: Text(
                            freq,
                            style: TextStyle(
                              fontSize: 12,
                              color: _selectedFrequency == freq ? Colors.white : Colors.grey[400],
                            ),
                          ),
                          selected: _selectedFrequency == freq,
                          onSelected: (selected) {
                            setState(() {
                              _selectedFrequency = selected ? freq : 'today';
                              if (freq != 'custom') {
                                _selectedDays.clear();
                              }
                            });
                          },
                          selectedColor: Colors.blue[700],
                          backgroundColor: Colors.grey[800],
                          checkmarkColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            
            // Custom day selection when 'custom' frequency is selected
            if (_selectedFrequency == 'custom') ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _weekDays.map((day) {
                  final isSelected = _selectedDays.contains(day);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedDays.remove(day);
                        } else {
                          _selectedDays.add(day);
                        }
                      });
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected ? Colors.blue[700] : Colors.grey[800],
                        border: Border.all(
                          color: isSelected ? Colors.blue[500]! : Colors.grey[600]!,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          day[0], // First letter of the day
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.grey[400],
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),

            // Notifications (multi-select list + add button)
            const SizedBox(height: 8),
            if (_selectedNotifications.isEmpty) ...[
              TextButton.icon(
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                icon: const Icon(Icons.notifications, size: 20),
                label: const Text('Add Notification'),
                onPressed: () => _showNotificationPicker(context),
              ),
            ] else ...[
              Column(
                children: [
                  for (int i = 0; i < _selectedNotifications.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Row(
                        children: [
                          Expanded(child: Text(_selectedNotifications[i])),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              setState(() {
                                _selectedNotifications.removeAt(i);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  // add button at the end
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                      icon: const Icon(Icons.notifications, size: 20),
                      label: const Text('Add Notification'),
                      onPressed: () => _showNotificationPicker(context),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}