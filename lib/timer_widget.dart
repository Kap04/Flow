import 'package:flutter/material.dart';
import 'package:circular_countdown_timer/circular_countdown_timer.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'gradients.dart';
import 'dnd_helper.dart';
import 'package:flutter/services.dart';

enum TimerMode { countdown, countup }

class TimerWidget extends StatefulWidget {
  final int durationMinutes;
  final TimerMode mode;
  final VoidCallback? onComplete;
  final VoidCallback? onStop;
  final VoidCallback? onAbort;
  final bool showAbortButton;
  final bool showAddTimeTooltip;
  final bool showAmbientSound;
  final String? sessionName;
  final String? tag;
  final bool isPaused;
  final Function(bool)? onPauseResume;
  final VoidCallback? onAddTenMinutes;
  final VoidCallback? onToggleAmbient;
  final VoidCallback? onToggleDnd; // optional external hook when DND toggled
  final bool ambientSound;
  final bool showSessionName; // New parameter to control session name display
  final bool showAmbientSoundButton; // New parameter to control ambient sound button in controls
  final bool showControlButtons; // New parameter to control control buttons display
  final GlobalKey<TimerWidgetState>? timerKey; // Add key for external access

  const TimerWidget({
    super.key,
    required this.durationMinutes,
    required this.mode,
    this.onComplete,
    this.onStop,
    this.onAbort,
    this.showAbortButton = false,
    this.showAddTimeTooltip = false,
    this.showAmbientSound = true,
    this.sessionName,
    this.tag,
    this.isPaused = false,
    this.onPauseResume,
    this.onAddTenMinutes,
  this.onToggleAmbient,
  this.onToggleDnd,
    this.ambientSound = false,
    this.showSessionName = true, // Default to true for backward compatibility
    this.showAmbientSoundButton = true, // Default to true for backward compatibility
    this.showControlButtons = true, // Default to true for backward compatibility
    this.timerKey, // Add key parameter
  });

  @override
  State<TimerWidget> createState() => TimerWidgetState();
}

class TimerWidgetState extends State<TimerWidget> {
  late CountDownController _countDownController;
  late AudioPlayer _audioPlayer;
  bool _initialized = false;
  int _countUpSeconds = 0;
  Timer? _countUpTimer;
  Timer? _tooltipTimer;
  bool _showAddTimeTooltip = false;
  int _lastDuration = 0;
  String _lastSessionKey = ''; // Track session changes
  bool _dndEnabledByApp = false; // track if app enabled DND

  // Expose the controller for external control
  CountDownController get controller => _countDownController;

  // Public helper to start a new session with a different session name/tag/duration
  void startNewSession({required String sessionName, required String tag, required int durationMinutes, required TimerMode mode}) {
    final newKey = '$sessionName-$tag-$durationMinutes';
    _lastSessionKey = newKey;
    _lastDuration = durationMinutes;
    _initialized = true;
    // restart the countdown controller
    if (mode == TimerMode.countdown) {
      _countUpTimer?.cancel();
      _countDownController.restart(duration: durationMinutes * 60);
      _countDownController.start();
    } else {
      _countUpSeconds = 0;
      _startCountUp();
    }
  }
  
  // Method to handle external pause/resume calls
  void togglePause() {
    if (widget.mode == TimerMode.countdown) {
      if (widget.isPaused) {
        _countDownController.resume();
      } else {
        _countDownController.pause();
      }
    }
    widget.onPauseResume?.call(!widget.isPaused);
  }

  @override
  void initState() {
    super.initState();
    _countDownController = CountDownController();
    _audioPlayer = AudioPlayer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Create a session key to detect session changes
    final sessionKey = '${widget.sessionName}-${widget.tag}-${widget.durationMinutes}';
    print('🎯 TimerWidget: Current sessionKey="$sessionKey", lastSessionKey="$_lastSessionKey"');
    
    // Check if session has changed (for new sessions)
    if (_lastSessionKey != sessionKey) {
      print('🎯 TimerWidget: Session changed from "$_lastSessionKey" to "$sessionKey"');
      _lastSessionKey = sessionKey;
      _lastDuration = widget.durationMinutes;
      _initialized = false; // Reset initialization to restart timer
      
      // Reset countdown controller for new session
      if (widget.mode == TimerMode.countdown) {
        print('🎯 TimerWidget: Restarting countdown with ${widget.durationMinutes * 60} seconds');
        _countDownController.restart(duration: widget.durationMinutes * 60);
        // Force start the timer immediately
        _countDownController.start();
      } else {
        _countUpSeconds = 0;
      }
    }
    
    if (!_initialized) {
      _initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.mode == TimerMode.countdown) {
          _countDownController.start();
        } else {
          _startCountUp();
        }
        
        if (widget.showAddTimeTooltip) {
          _startTooltipTimer();
        }
      });
    }
  }

  void _startCountUp() {
    _countUpTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!widget.isPaused) {
        setState(() => _countUpSeconds++);
      }
    });
  }

  void _startTooltipTimer() {
    _tooltipTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        if (widget.mode == TimerMode.countdown) {
          final remainingTime = _countDownController.getTime();
          if (remainingTime != null) {
            final parts = remainingTime.split(':');
            if (parts.length == 2) {
              final minutes = int.parse(parts[0]);
              final seconds = int.parse(parts[1]);
              final totalSeconds = minutes * 60 + seconds;
              
              if (totalSeconds <= 300 && totalSeconds > 0) {
                setState(() => _showAddTimeTooltip = true);
              } else {
                setState(() => _showAddTimeTooltip = false);
              }
            }
          }
        } else {
          // For countup, show tooltip when 5 minutes or less remain
          final remaining = widget.durationMinutes * 60 - _countUpSeconds;
          if (remaining <= 300 && remaining > 0) {
            setState(() => _showAddTimeTooltip = true);
          } else {
            setState(() => _showAddTimeTooltip = false);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _countUpTimer?.cancel();
    _tooltipTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  String _formatCountUp(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    print('🎯 TimerWidget build: sessionName=${widget.sessionName}, tag=${widget.tag}, duration=${widget.durationMinutes}');
    return Column(
      children: [
        // Timer Display
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
                             if (widget.mode == TimerMode.countdown)
                 CircularCountDownTimer(
                   duration: widget.durationMinutes * 60,
                   controller: _countDownController,
                   width: 200,
                   height: 200,
                   ringColor: const Color(0xFF222222), // Dark gray ring
                   fillColor: const Color.fromRGBO(10, 172, 223, 1), // Sky blue fill
                   backgroundColor: Colors.grey[800]!,
                   strokeWidth: 8,
                   strokeCap: StrokeCap.round,
                   isTimerTextShown: true,
                   isReverse: true,
                   isReverseAnimation: true,

                   textStyle: const TextStyle(fontSize: 48, color: Colors.white),
                   onComplete: widget.onComplete,
                   onChange: (time) {
                     // Handle tooltip logic in periodic timer
                   },
                 )
              else
                Center(
                  child: Text(
                    _formatCountUp(_countUpSeconds),
                    style: const TextStyle(fontSize: 48, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              
              // +10 minutes tooltip
              if (_showAddTimeTooltip && widget.onAddTenMinutes != null)
                Positioned(
                  bottom: 20,
                  child: GestureDetector(
                    onTap: widget.onAddTenMinutes,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        '+10 minutes',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        
        // Controls
        if (widget.showControlButtons)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Abort button (only visible if enabled)
                if (widget.showAbortButton && widget.onAbort != null)
                  GestureDetector(
                    onTap: widget.onAbort,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                
                // Pause/Resume
                if (widget.onPauseResume != null)
                  GestureDetector(
                    onTap: () {
                      if (widget.mode == TimerMode.countdown) {
                        if (widget.isPaused) {
                          _countDownController.resume();
                        } else {
                          _countDownController.pause();
                        }
                      }
                      widget.onPauseResume!(!widget.isPaused);
                    },
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: kAccentGradient,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Icon(
                        widget.isPaused ? Icons.play_arrow : Icons.pause,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                
                // Stop
                if (widget.onStop != null)
                  GestureDetector(
                    onTap: widget.onStop,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Center(
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                
                // Ambient Sound
                if (widget.showAmbientSound && widget.onToggleAmbient != null && widget.showAmbientSoundButton)
                  GestureDetector(
                    onTap: widget.onToggleAmbient,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: widget.ambientSound ? Colors.blue : Colors.grey[800],
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Icon(
                        Icons.volume_up,
                        color: widget.ambientSound ? Colors.white : Colors.grey,
                        size: 30,
                      ),
                    ),
                  ),
                // Do Not Disturb toggle
                GestureDetector(
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      // Check access
                      final granted = await DndHelper.isAccessGranted();
                      if (!granted) {
                        // open settings so user can grant
                        await DndHelper.openSettings();
                        return;
                      }
                      if (!_dndEnabledByApp) {
                        await DndHelper.enableDnd();
                        _dndEnabledByApp = true;
                        widget.onToggleDnd?.call();
                        setState(() {});
                      } else {
                        await DndHelper.disableDnd();
                        _dndEnabledByApp = false;
                        widget.onToggleDnd?.call();
                        setState(() {});
                      }
                    } catch (e) {
                      // ignore: avoid_print
                      print('TimerWidget: DND action failed: $e');
                      if (e is MissingPluginException) {
                        messenger.showSnackBar(const SnackBar(content: Text('DND native handler not available — stop and rebuild the app to enable.')));
                      } else {
                        messenger.showSnackBar(const SnackBar(content: Text('DND action failed')));
                      }
                    }
                  },
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: _dndEnabledByApp ? Colors.redAccent : Colors.grey[800],
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Icon(
                      Icons.do_not_disturb_on,
                      color: _dndEnabledByApp ? Colors.white : Colors.grey,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
} 