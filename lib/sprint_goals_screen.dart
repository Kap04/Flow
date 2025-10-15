import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// removed unused dart:math import
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
                style: TextStyle(
                  color: _goalController.text.trim() == 'Read 50 pages' || _goalController.text.trim().isEmpty ? Colors.white54 : Colors.white,
                  fontSize: 18,
                  fontStyle: _goalController.text.trim() == 'Read 50 pages' || _goalController.text.trim().isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
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
                    return _BreakDivider(sprint: prevSprint);
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
                ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow, color: Colors.black),
                  label: const Text('Start Sprint'),
                  onPressed: () {
                    final goal = ref.read(goalProvider);
                    if (goal.sprints.isNotEmpty) {
                      // Create sprint sequence
                      final sessions = createSprintSequence(goal.goalName, goal.sprints);
                      ref.read(sprintSequenceProvider.notifier).startSequence(sessions);
                      
                      // Navigate to first session
                      final firstSession = sessions.first;
                      print('▶️ Starting sprint sequence: ${firstSession.sprintName} — duration ${firstSession.durationMinutes} minutes');
                      GoRouter.of(context).push('/sprint-timer?goalName=${Uri.encodeComponent(firstSession.goalName)}&sprintName=${Uri.encodeComponent(firstSession.sprintName)}&durationMinutes=${firstSession.durationMinutes}&sprintIndex=${firstSession.sprintIndex}&phase=${firstSession.phase.name}');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 2,
                  ),
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
  bool editingName = false;
  bool editingDuration = false;
  late TextEditingController nameController;
  late TextEditingController durationController;
  late FocusNode nameFocus;
  late FocusNode durationFocus;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.sprint.name);
    durationController = TextEditingController(text: widget.sprint.duration.toString());
    nameFocus = FocusNode();
    durationFocus = FocusNode();

    nameFocus.addListener(() {
      if (!nameFocus.hasFocus && editingName) {
        _saveName();
      }
    });

    durationFocus.addListener(() {
      if (!durationFocus.hasFocus && editingDuration) {
        _saveDuration();
      }
    });
  }

  @override
  void dispose() {
    nameController.dispose();
    durationController.dispose();
    nameFocus.dispose();
    durationFocus.dispose();
    super.dispose();
  }

  void _saveName() {
    final notifier = ref.read(goalProvider.notifier);
    final newName = nameController.text.trim();
    if (newName.isNotEmpty && newName != widget.sprint.name) {
      notifier.updateSprint(widget.sprint.id, name: newName);
    }
    setState(() {
      editingName = false;
    });
  }

  void _saveDuration() {
    final notifier = ref.read(goalProvider.notifier);
    final newDur = int.tryParse(durationController.text.trim());
    if (newDur != null && newDur > 0 && newDur != widget.sprint.duration) {
      notifier.updateSprint(widget.sprint.id, duration: newDur);
    }
    setState(() {
      editingDuration = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(goalProvider.notifier);

    return Card(
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  // Name area (tap to edit inline)
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          editingName = true;
                          // update controller text in case provider changed
                          nameController.text = widget.sprint.name;
                          WidgetsBinding.instance.addPostFrameCallback((_) => nameFocus.requestFocus());
                        });
                      },
                      child: editingName
                          ? TextField(
                              controller: nameController,
                              focusNode: nameFocus,
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4), border: InputBorder.none),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _saveName(),
                            )
                          : Text(
                              '${widget.sprint.name}',
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                            ),
                    ),
                  ),
                    const SizedBox(width: 8),
                    // Duration area (tap to edit inline) — centered block
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          editingDuration = true;
                          durationController.text = widget.sprint.duration.toString();
                          WidgetsBinding.instance.addPostFrameCallback((_) => durationFocus.requestFocus());
                        });
                      },
                      child: SizedBox(
                        width: 110,
                        child: Center(
                          child: editingDuration
                              ? SizedBox(
                                  width: 70,
                                  child: TextField(
                                    controller: durationController,
                                    focusNode: durationFocus,
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4), border: InputBorder.none),
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => _saveDuration(),
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.hourglass_bottom, color: Colors.white54, size: 16),
                                    const SizedBox(width: 6),
                                    Text('${widget.sprint.duration} min', style: const TextStyle(color: Colors.white54, fontSize: 14)),
                                  ],
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
              onPressed: () => notifier.removeSprint(widget.sprint.id),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakDivider extends ConsumerStatefulWidget {
  final Sprint sprint;
  const _BreakDivider({required this.sprint});
  @override
  ConsumerState<_BreakDivider> createState() => _BreakDividerState();
}

class _BreakDividerState extends ConsumerState<_BreakDivider> {
  bool editing = false;
  late TextEditingController _controller;
  late FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.sprint.breakDuration.toString());
    _focus = FocusNode();
    _focus.addListener(() {
      if (!_focus.hasFocus && editing) {
        _save();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _save() {
    final val = int.tryParse(_controller.text.trim());
    if (val != null && val > 0) {
      ref.read(goalProvider.notifier).updateBreak(widget.sprint.id, val);
    } else {
      // reset controller to current value
      _controller.text = widget.sprint.breakDuration.toString();
    }
    setState(() => editing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Row(
          children: [
            Expanded(child: Container(height: 1, margin: const EdgeInsets.only(right: 8), color: Colors.white12)),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                setState(() {
                  editing = true;
                  _controller.text = widget.sprint.breakDuration.toString();
                  WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
                });
              },
              child: editing
                  ? SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8), border: InputBorder.none),
                        onSubmitted: (_) => _save(),
                      ),
                    )
                  : Row(
                      children: [
                        const Icon(Icons.bedtime, color: Colors.white38, size: 16),
                        const SizedBox(width: 6),
                        Text('${widget.sprint.breakDuration} min break', style: const TextStyle(color: Colors.white38, fontSize: 13)),
                      ],
                    ),
            ),
            const SizedBox(width: 6),
            Expanded(child: Container(height: 1, margin: const EdgeInsets.only(left: 8), color: Colors.white12)),
          ],
        ),
      ),
    );
  }
}