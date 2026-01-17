import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'planner_model.dart';

class GoogleCalendarService {
  static const _scopes = [calendar.CalendarApi.calendarScope];
  
  GoogleSignIn? _googleSignIn;
  calendar.CalendarApi? _calendarApi;
  
  Future<bool> isCalendarIntegrated(String userId) async {
    // Check if user has enabled calendar integration
    // This can be stored in Firestore user preferences
    return false; // TODO: implement preference check
  }
  
  Future<calendar.CalendarApi?> _getCalendarApi() async {
    try {
      _googleSignIn ??= GoogleSignIn(scopes: _scopes);
      
      final account = await _googleSignIn!.signInSilently();
      if (account == null) {
        return null;
      }
      
      final authHeaders = await account.authHeaders;
      final authenticateClient = GoogleAuthClient(authHeaders);
      
      _calendarApi = calendar.CalendarApi(authenticateClient);
      return _calendarApi;
    } catch (e) {
      print('Error getting calendar API: $e');
      return null;
    }
  }
  
  Future<bool> requestCalendarAccess() async {
    try {
      _googleSignIn ??= GoogleSignIn(scopes: _scopes);
      final account = await _googleSignIn!.signIn();
      return account != null;
    } catch (e) {
      print('Error requesting calendar access: $e');
      return false;
    }
  }
  
  Future<void> syncTriggerToCalendar(ScheduledSession session) async {
    try {
      final api = await _getCalendarApi();
      if (api == null) return;
      
      final event = calendar.Event()
        ..summary = session.title
        ..description = 'Flow Trigger: ${session.tag}'
        ..start = calendar.EventDateTime(dateTime: session.startAt, timeZone: session.timezone)
        ..end = calendar.EventDateTime(
          dateTime: session.startAt.add(Duration(
            minutes: session.items.fold(0, (sum, item) => sum + item.durationMinutes),
          )),
          timeZone: session.timezone,
        )
        ..extendedProperties = calendar.EventExtendedProperties()
        ..extendedProperties!.private = {
          'flowTriggerId': session.id,
          'flowApp': 'true',
        };
      
      // Add reminders
      if (session.reminderOffsets.isNotEmpty) {
        event.reminders = calendar.EventReminders()
          ..useDefault = false
          ..overrides = session.reminderOffsets.map((offset) {
            return calendar.EventReminder()
              ..method = 'popup'
              ..minutes = offset;
          }).toList();
      }
      
      await api.events.insert(event, 'primary');
    } catch (e) {
      print('Error syncing trigger to calendar: $e');
    }
  }
  
  Future<void> updateCalendarEvent(ScheduledSession session) async {
    try {
      final api = await _getCalendarApi();
      if (api == null) return;
      
      // Find event by flowTriggerId
      final events = await api.events.list(
        'primary',
        privateExtendedProperty: ['flowTriggerId=${session.id}'],
      );
      
      if (events.items == null || events.items!.isEmpty) {
        // Event doesn't exist, create it
        await syncTriggerToCalendar(session);
        return;
      }
      
      final existingEvent = events.items!.first;
      final event = calendar.Event()
        ..summary = session.title
        ..description = 'Flow Trigger: ${session.tag}'
        ..start = calendar.EventDateTime(dateTime: session.startAt, timeZone: session.timezone)
        ..end = calendar.EventDateTime(
          dateTime: session.startAt.add(Duration(
            minutes: session.items.fold(0, (sum, item) => sum + item.durationMinutes),
          )),
          timeZone: session.timezone,
        )
        ..extendedProperties = calendar.EventExtendedProperties()
        ..extendedProperties!.private = {
          'flowTriggerId': session.id,
          'flowApp': 'true',
        };
      
      await api.events.update(event, 'primary', existingEvent.id!);
    } catch (e) {
      print('Error updating calendar event: $e');
    }
  }
  
  Future<void> deleteCalendarEvent(String sessionId) async {
    try {
      final api = await _getCalendarApi();
      if (api == null) return;
      
      final events = await api.events.list(
        'primary',
        privateExtendedProperty: ['flowTriggerId=$sessionId'],
      );
      
      if (events.items != null && events.items!.isNotEmpty) {
        await api.events.delete('primary', events.items!.first.id!);
      }
    } catch (e) {
      print('Error deleting calendar event: $e');
    }
  }
  
  Future<List<calendar.Event>> getCalendarEvents(DateTime start, DateTime end) async {
    try {
      final api = await _getCalendarApi();
      if (api == null) return [];
      
      final events = await api.events.list(
        'primary',
        timeMin: start.toUtc(),
        timeMax: end.toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
      );
      
      return events.items ?? [];
    } catch (e) {
      print('Error getting calendar events: $e');
      return [];
    }
  }
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}
