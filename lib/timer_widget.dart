import 'package:flutter/material.dart';
import 'package:circular_countdown_timer/circular_countdown_timer.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'gradients.dart';

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
  final bool ambientSound;

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
    this.ambientSound = false,
  });

  @override
  State<TimerWidget> createState() => _TimerWidgetState();
}

class _TimerWidgetState extends State<TimerWidget> {
  late CountDownController _countDownController;
  late AudioPlayer _audioPlayer;
  bool _initialized = false;
  int _countUpSeconds = 0;
  Timer? _countUpTimer;
  Timer? _tooltipTimer;
  bool _showAddTimeTooltip = false;
  int _lastDuration = 0;
  String _lastSessionKey = ''; // Track session changes

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
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              
              // Ambient Sound
              if (widget.showAmbientSound && widget.onToggleAmbient != null)
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
            ],
          ),
        ),
      ],
    );
  }
} 