import 'dart:async';
// removed unused material import
import 'notification_service.dart';

class TimerNotificationManager {
  Timer? _timer;
  int _secondsLeft = 0;
  String _title = 'Sprint running';
  String _body = 'Focus session';

  void start(int seconds, {String? title, String? body}) {
    _secondsLeft = seconds;
    if (title != null) _title = title;
    if (body != null) _body = body;
    _timer?.cancel();
    NotificationService.showTimerNotification(
      title: _title,
      body: _body,
      secondsLeft: _secondsLeft,
      ongoing: true,
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      _secondsLeft = (_secondsLeft - 1).clamp(0, _secondsLeft);
      NotificationService.showTimerNotification(
        title: _title,
        body: _body,
        secondsLeft: _secondsLeft,
        ongoing: true,
      );
      if (_secondsLeft <= 0) stop();
    });
  }

  void stop() {
    _timer?.cancel();
    NotificationService.cancelTimerNotification();
  }
}
