import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// removed unused dart:math import
import 'sprint_sequence_provider.dart';
import 'app_drawer.dart';
import 'planner/planner_model.dart';
import 'home_screen.dart';

class Sprint {
  String id;
  String name;
  int duration; // in minutes
  int breakDuration; // in minutes
  String tag; // in minutes
  Sprint({required this.id, required this.name, required this.duration, required this.breakDuration, required this.tag});
}

class GoalState {
  String goalName;
  String goalTag;
  List<Sprint> sprints;
  GoalState({required this.goalName, required this.goalTag, required this.sprints});
  GoalState copyWith({String? goalName, String? goalTag, List<Sprint>? sprints}) => GoalState(
    goalName: goalName ?? this.goalName,
    goalTag: goalTag ?? this.goalTag,
    sprints: sprints ?? this.sprints,
  );
}

class GoalNotifier extends StateNotifier<GoalState> {
  GoalNotifier()
      : super(GoalState(goalName: '', goalTag: kPredefinedTags[0], sprints: List.generate(4, (i) => Sprint(
          id: UniqueKey().toString(),
          name: 'Block ${i + 1}',
          duration: 25,
          breakDuration: 5,
          tag: kPredefinedTags[0],
        ))));

  void setGoalName(String name) => state = state.copyWith(goalName: name);
  void setGoalTag(String tag) {
    state = state.copyWith(goalTag: tag);
    updateAllSprintTags();
  }
  
  void initializeFromScheduledSession({required String goalName, required List<Sprint> sprints}) {
    state = GoalState(goalName: goalName, goalTag: kPredefinedTags[0], sprints: sprints);
  }
  
  void addSprint() {
    final lastBreak = state.sprints.isNotEmpty ? state.sprints.last.breakDuration : 5;
    // Update all existing sprints to use current goalTag
    final updatedSprints = state.sprints.map((s) => Sprint(
      id: s.id,
      name: s.name,
      duration: s.duration,
      breakDuration: s.breakDuration,
      tag: state.goalTag,
    )).toList();
    state = state.copyWith(sprints: [
      ...updatedSprints,
      Sprint(id: UniqueKey().toString(), name: 'Block ${state.sprints.length + 1}', duration: 25, breakDuration: lastBreak, tag: state.goalTag),
    ]);
  }
  
  void updateAllSprintTags() {
    // Update all sprints to use current goalTag
    final updatedSprints = state.sprints.map((s) => Sprint(
      id: s.id,
      name: s.name,
      duration: s.duration,
      breakDuration: s.breakDuration,
      tag: state.goalTag,
    )).toList();
    state = state.copyWith(sprints: updatedSprints);
  }
  void removeSprint(String id) => state = state.copyWith(sprints: state.sprints.where((s) => s.id != id).toList());
  void updateSprint(String id, {String? name, int? duration, String? tag}) {
    state = state.copyWith(sprints: [
      for (final s in state.sprints)
        if (s.id == id)
          Sprint(
            id: s.id,
            name: name ?? s.name,
            duration: duration ?? s.duration,
            breakDuration: s.breakDuration,
            tag: tag ?? s.tag,
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
            tag: s.tag,
          )
        else
          s,
    ]);
  }
}

final goalProvider = StateNotifierProvider<GoalNotifier, GoalState>((ref) => GoalNotifier());

class SprintGoalsScreen extends ConsumerStatefulWidget {
  final ScheduledSession? scheduledSession;
  final String? preCreatedSprintId;
  
  const SprintGoalsScreen({
    super.key,
    this.scheduledSession,
    this.preCreatedSprintId,
  });

  @override
  ConsumerState<SprintGoalsScreen> createState() => _SprintGoalsScreenState();
}

class _SprintGoalsScreenState extends ConsumerState<SprintGoalsScreen> {
  late TextEditingController _goalController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _customTag;

  @override
  void initState() {
    super.initState();
    
    // Check if we're coming from a notification with scheduled session data
    if (widget.scheduledSession != null) {
      final session = widget.scheduledSession!;
      
      // Convert scheduled session items to sprints
      final sprints = session.items.map((item) {
        return Sprint(
          id: UniqueKey().toString(),
          name: item.label ?? 'Sprint ${session.items.indexOf(item) + 1}',
          duration: item.durationMinutes,
          breakDuration: item.breakAfterMinutes ?? 5,
          tag: kPredefinedTags[0], // Default to first tag (Unset)
        );
      }).toList();
      
      // Update the goal provider with the scheduled session data
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(goalProvider.notifier).initializeFromScheduledSession(
          goalName: session.title,
          sprints: sprints,
        );
      });
      
      _goalController = TextEditingController(text: session.title);
    } else {
      // Normal initialization
      final goal = ref.read(goalProvider);
      _goalController = TextEditingController(text: goal.goalName);
    }
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
        title: const Text('Time Blocks', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Goal input with tag dropdown
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  // Goal input field
                  Expanded(
                    child: TextField(
                      controller: _goalController,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Read 50 pages',
                        hintStyle: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic),
                        border: InputBorder.none,
                      ),
                      onChanged: (v) => ref.read(goalProvider.notifier).setGoalName(v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Tag dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[700]!, width: 1),
                    ),
                    child: DropdownButton<String>(
                      value: _customTag ?? goal.goalTag,
                      dropdownColor: Colors.grey[900],
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      underline: const SizedBox(),
                      iconEnabledColor: Colors.white70,
                      isDense: true,
                      items: kPredefinedTags.map((tag) {
                        return DropdownMenuItem(
                          value: tag,
                          child: Text(tag),
                        );
                      }).toList(),
                      onChanged: (value) async {
                        if (value == 'Other') {
                          final custom = await showDialog<String>(
                            context: context,
                            builder: (ctx) {
                              final controller = TextEditingController();
                              return AlertDialog(
                                backgroundColor: Colors.grey[900],
                                title: const Text('Custom Tag', style: TextStyle(color: Colors.white)),
                                content: TextField(
                                  controller: controller,
                                  autofocus: true,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: const InputDecoration(
                                    hintText: 'Enter tag name',
                                    hintStyle: TextStyle(color: Colors.white54),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                                    child: const Text('Save'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (custom != null && custom.isNotEmpty) {
                            setState(() => _customTag = custom);
                            ref.read(goalProvider.notifier).setGoalTag(custom);
                          }
                        } else if (value != null) {
                          setState(() => _customTag = null);
                          ref.read(goalProvider.notifier).setGoalTag(value);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: goal.sprints.isEmpty
                  ? Center(
                      child: Text(
                        'No blocks yet. Add a block to get started.',
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      ),
                    )
                  : ListView.builder(
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
                  label: const Text('Add Block', style: TextStyle(color: Colors.white)),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  icon: Icon(Icons.play_arrow, color: goal.sprints.isEmpty ? Colors.grey[600] : Colors.black),
                  label: const Text('Start Time Blocks'),
                  onPressed: goal.sprints.isEmpty ? null : () {
                    // Create sprint sequence
                    final sessions = createSprintSequence(goal.goalName, goal.sprints);
                    ref.read(sprintSequenceProvider.notifier).startSequence(sessions);
                    
                    // Navigate to first session
                    final firstSession = sessions.first;
                    print('▶️ Starting sprint sequence: ${firstSession.sprintName} — duration ${firstSession.durationMinutes} minutes');
                    
                    // Include preCreatedSprintId if we came from a notification
                    final preCreatedParam = widget.preCreatedSprintId != null && widget.preCreatedSprintId!.isNotEmpty 
                        ? '&preCreatedSprintId=${Uri.encodeComponent(widget.preCreatedSprintId!)}' 
                        : '';
                    
                    GoRouter.of(context).push('/sprint-timer?goalName=${Uri.encodeComponent(firstSession.goalName)}&sprintName=${Uri.encodeComponent(firstSession.sprintName)}&durationMinutes=${firstSession.durationMinutes}&sprintIndex=${firstSession.sprintIndex}&phase=${firstSession.phase.name}$preCreatedParam');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: goal.sprints.isEmpty ? Colors.grey[800] : Colors.white,
                    foregroundColor: goal.sprints.isEmpty ? Colors.grey[600] : Colors.black,
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

  // Helper method to check if this is a default block name that should be styled as placeholder
  bool _isDefaultBlockName(String name) {
    return RegExp(r'^Block \d+$').hasMatch(name);
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
                              widget.sprint.name,
                              style: TextStyle(
                                color: _isDefaultBlockName(widget.sprint.name) ? Colors.grey : Colors.white,
                                fontSize: 16,
                                fontStyle: _isDefaultBlockName(widget.sprint.name) ? FontStyle.italic : FontStyle.normal,
                              ),
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