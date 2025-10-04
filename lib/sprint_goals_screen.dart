import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:math';
import 'sprint_sequence_provider.dart';
import 'app_drawer.dart';

class Sprint {
  String id;
  String name;
  int duration; // in minutes
  int breakDuration; // in minutes
  Sprint({required this.id, required this.name, required this.duration, required this.breakDuration});
}

class GoalState {
  String goalName;
  List<Sprint> sprints;
  GoalState({required this.goalName, required this.sprints});
  GoalState copyWith({String? goalName, List<Sprint>? sprints}) => GoalState(
    goalName: goalName ?? this.goalName,
    sprints: sprints ?? this.sprints,
  );
}

class GoalNotifier extends StateNotifier<GoalState> {
  GoalNotifier()
      : super(GoalState(goalName: 'Read 50 pages', sprints: List.generate(4, (i) => Sprint(
          id: UniqueKey().toString(),
          name: 'Sprint ${i + 1}',
          duration: 25,
          breakDuration: 5,
        ))));

  void setGoalName(String name) => state = state.copyWith(goalName: name);
  void addSprint() {
    final lastBreak = state.sprints.isNotEmpty ? state.sprints.last.breakDuration : 5;
    state = state.copyWith(sprints: [
      ...state.sprints,
      Sprint(id: UniqueKey().toString(), name: 'Sprint ${state.sprints.length + 1}', duration: 25, breakDuration: lastBreak),
    ]);
  }
  void removeSprint(String id) => state = state.copyWith(sprints: state.sprints.where((s) => s.id != id).toList());
  void updateSprint(String id, {String? name, int? duration}) {
    state = state.copyWith(sprints: [
      for (final s in state.sprints)
        if (s.id == id)
          Sprint(
            id: s.id,
            name: name ?? s.name,
            duration: duration ?? s.duration,
            breakDuration: s.breakDuration,
          )
        else
          s,
    ]);
  }
  void updateBreak(String id, int breakDuration) {
    state = state.copyWith(sprints: [
      for (final s in state.sprints)
        if (s.id == id)
          Sprint(
            id: s.id,
            name: s.name,
            duration: s.duration,
            breakDuration: breakDuration,
          )
        else
          s,
    ]);
  }
}

final goalProvider = StateNotifierProvider<GoalNotifier, GoalState>((ref) => GoalNotifier());

class SprintGoalsScreen extends ConsumerStatefulWidget {
  const SprintGoalsScreen({super.key});

  @override
  ConsumerState<SprintGoalsScreen> createState() => _SprintGoalsScreenState();
}

class _SprintGoalsScreenState extends ConsumerState<SprintGoalsScreen> {
  late TextEditingController _goalController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    final goal = ref.read(goalProvider);
    _goalController = TextEditingController(text: goal.goalName);
  }

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final goal = ref.watch(goalProvider);
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.black,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Sprint Goals', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: TextField(
                controller: _goalController,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: const InputDecoration(
                  hintText: 'Goal',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onSubmitted: (v) => ref.read(goalProvider.notifier).setGoalName(v),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: goal.sprints.length * 2 - 1,
                itemBuilder: (context, i) {
                  if (i.isEven) {
                    final idx = i ~/ 2;
                    final sprint = goal.sprints[idx];
                    return _SprintTile(sprint: sprint);
                  } else {
                    final prevSprint = goal.sprints[(i - 1) ~/ 2];
                    return GestureDetector(
                      onLongPress: () async {
                        final newBreak = await showDialog<int>(
                          context: context,
                          builder: (ctx) {
                            int val = prevSprint.breakDuration;
                            return AlertDialog(
                              backgroundColor: Colors.black,
                              title: const Text('Set Break Duration', style: TextStyle(color: Colors.white)),
                              content: Row(
                                children: [
                                  Expanded(
                                    child: Slider(
                                      value: val.toDouble(),
                                      min: 1,
                                      max: 30,
                                      divisions: 29,
                                      label: '$val min',
                                      onChanged: (v) => val = v.round(),
                                    ),
                                  ),
                                  Text('$val min', style: const TextStyle(color: Colors.white)),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, val),
                                  child: const Text('OK', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            );
                          },
                        );
                        if (newBreak != null) {
                          ref.read(goalProvider.notifier).updateBreak(prevSprint.id, newBreak);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Center(
                          child: Text(
                            '-------${prevSprint.breakDuration} min break---------',
                            style: const TextStyle(color: Colors.white38, fontSize: 13, fontStyle: FontStyle.italic),
                          ),
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => ref.read(goalProvider.notifier).addSprint(),
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('Add Sprint', style: TextStyle(color: Colors.white)),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () {
                    final goal = ref.read(goalProvider);
                    if (goal.sprints.isNotEmpty) {
                      // Create sprint sequence
                      final sessions = createSprintSequence(goal.goalName, goal.sprints);
                      ref.read(sprintSequenceProvider.notifier).startSequence(sessions);
                      
                      // Navigate to first session
                      final firstSession = sessions.first;
                      print('▶️ Starting sprint sequence: ${firstSession.sprintName} — duration ${firstSession.durationMinutes} minutes');
                      GoRouter.of(context).go('/sprint-timer?goalName=${Uri.encodeComponent(firstSession.goalName)}&sprintName=${Uri.encodeComponent(firstSession.sprintName)}&durationMinutes=${firstSession.durationMinutes}&sprintIndex=${firstSession.sprintIndex}&phase=${firstSession.phase.name}');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white10,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Start Sprint'),
                ),
              ],
            ),
            ],
        ),
      ),
    );
  }
}

class _SprintTile extends ConsumerStatefulWidget {
  final Sprint sprint;
  const _SprintTile({required this.sprint});
  @override
  ConsumerState<_SprintTile> createState() => _SprintTileState();
}

class _SprintTileState extends ConsumerState<_SprintTile> {
  bool _editing = false;
  late TextEditingController _nameController;
  late TextEditingController _durationController;
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.sprint.name);
    _durationController = TextEditingController(text: widget.sprint.duration.toString());
  }
  @override
  void dispose() {
    _nameController.dispose();
    _durationController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(goalProvider.notifier);
    return Card(
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.sprint.name} - ${widget.sprint.duration} min',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white38, size: 20),
                  onPressed: () => setState(() => _editing = !_editing),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                  onPressed: () => notifier.removeSprint(widget.sprint.id),
                ),
              ],
            ),
            if (_editing)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                          controller: _nameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Sprint Name',
                            hintStyle: TextStyle(color: Colors.white54),
                            border: OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (v) => notifier.updateSprint(widget.sprint.id, name: v),
                        ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 70,
                      child: TextField(
                        controller: _durationController,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          hintText: 'min',
                          hintStyle: TextStyle(color: Colors.white54),
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (v) {
                          final val = int.tryParse(v);
                          if (val != null && val > 0) {
                            notifier.updateSprint(widget.sprint.id, duration: val);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
} 