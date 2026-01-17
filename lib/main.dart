import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'onboarding_screen.dart';
import 'auth_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'in_session_screen.dart';
import 'history_screen.dart';
import 'sprint_goals_screen.dart';
import 'sprint_timer_screen.dart';
import 'sprint_preview_screen.dart';
import 'leaderboard_screen.dart';
import 'sounds_screen.dart';
import 'profile_screen.dart';
import 'notification_service.dart';
import 'advanced_settings_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'planner/planner_model.dart';
import 'planner/planner_screen.dart';
import 'planner/scheduled_notification_service.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_blocking_screen.dart';

// removed unused async import

final onboardingCompleteProvider = StateProvider<bool>((ref) => false);
final authProvider = StreamProvider<User?>((ref) => FirebaseAuth.instance.authStateChanges());

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

Future<ScheduledSession?> _fetchSession(String sessionId, String userId) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('scheduled_sessions')
        .doc(sessionId)
        .get();
    
    if (doc.exists) {
      return ScheduledSession.fromFirestore(doc);
    }
  } catch (e) {
    print('Error fetching session: $e');
  }
  return null;
}

Future<void> _launchSprintWithSession(ScheduledSession session) async {
  print('🚀 Launching sprint with session: ${session.title}');
  
  // If we have a pre-created sprint session, activate it
  if (session.sprintSessionId != null) {
    try {
      // Update sprint session status to 'active' and set start time
      await FirebaseFirestore.instance
          .collection('users')
          .doc(session.userId)
          .collection('sprint_sessions')
          .doc(session.sprintSessionId!)
          .update({
        'status': 'active',
        'startTime': DateTime.now().millisecondsSinceEpoch,
      });
      print('✓ Activated pre-created sprint session: ${session.sprintSessionId}');
    } catch (e) {
      print('✗ Failed to activate sprint session: $e');
    }
  }

  // Store session data globally for navigation
  _pendingNotificationSession = session;
  
  // Trigger navigation after a small delay to ensure app is ready
  await Future.delayed(const Duration(milliseconds: 300));
  
  try {
    // Navigate to the existing Sprint Goals screen with the scheduled session data
    final route = '/sprints?fromNotification=true&sessionId=${Uri.encodeComponent(session.id)}&preCreatedSprintId=${Uri.encodeComponent(session.sprintSessionId ?? '')}';
    
    print('🔗 Navigating to: $route');
    
    // Use the global router reference stored during app creation
    if (_globalRouter != null) {
      _globalRouter!.go(route);
      print('✓ Navigation via global router');
    } else {
      print('❌ Global router not available');
    }
  } catch (e) {
    print('❌ Navigation error: $e');
  }
}

Future<void> _onNotificationTap(String? payload, String? actionId) async {
  if (payload == null) return;
  
  try {
    final data = jsonDecode(payload) as Map<String, dynamic>;
    final sessionId = data['sessionId'] as String;
    final action = data['action'] as String;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final session = await _fetchSession(sessionId, user.uid);
    if (session == null) return;
    
    if (actionId == 'start_now' || actionId == 'start' || actionId == 'start_session' || action == 'countdown_complete' || action == 'time_to_start') {
      // Launch sprint immediately
      await _launchSprintWithSession(session);
    } else if (actionId == 'snooze') {
      // Schedule countdown notification for session start time
      await ScheduledNotificationService.scheduleStartTimeNotification(
        session: session,
        startTime: session.startAt,
      );
    }
  } catch (e) {
    print('Error handling notification: $e');
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global router reference for notification navigation
GoRouter? _globalRouter;
ScheduledSession? _pendingNotificationSession;

void main() async {
  print('🚀 App starting...');
  WidgetsFlutterBinding.ensureInitialized();
  
  print('🔥 Initializing Firebase...');
  await Firebase.initializeApp();
  
  print('🔔 Initializing NotificationService...');
  await NotificationService.init();
  
  print('🔔 Initializing ScheduledNotificationService...');
  // Initialize scheduled notifications with callback
  await ScheduledNotificationService.init(
    onNotificationResponse: (NotificationResponse response) {
      print('🔔 Notification tapped! Payload: ${response.payload}, Action: ${response.actionId}');
      _onNotificationTap(response.payload, response.actionId);
    },
  );
  print('🔔 ScheduledNotificationService initialized!');
  
  // Set up notification action method channel from native Android
  const notificationActionChannel = MethodChannel('com.example.flow_app/notification_action');
  notificationActionChannel.setMethodCallHandler((MethodCall call) async {
    print('🔔 Method call received: ${call.method} with args: ${call.arguments}');
    
    if (call.method == 'onNotificationAction') {
      try {
        // Handle the arguments properly - they come as Map<Object?, Object?>
        final dynamic args = call.arguments;
        if (args != null && args is Map) {
          final sessionId = args['sessionId']?.toString();
          final action = args['action']?.toString();
          
          print('🔔 Native notification action received - Session: $sessionId, Action: $action');
          
          if (sessionId != null && action != null) {
            final user = FirebaseAuth.instance.currentUser;
            print('🔔 Current user: ${user?.uid}');
            
            if (user != null) {
              print('🔔 Fetching session: $sessionId');
              final session = await _fetchSession(sessionId, user.uid);
              
              if (session != null) {
                print('🔔 Session found: ${session.title}');
                
                if (action == 'START_NOW') {
                  print('🔔 Launching sprint from native notification action');
                  await _launchSprintWithSession(session);
                } else if (action == 'SNOOZE') {
                  print('🔔 Snoozing session - scheduling start time notification');
                  // Schedule a "time to start" notification for the actual session start time
                  await ScheduledNotificationService.scheduleStartTimeNotification(
                    session: session,
                    startTime: session.startAt,
                  );
                }
              } else {
                print('❌ Session not found for ID: $sessionId');
              }
            } else {
              print('❌ No authenticated user');
            }
          } else {
            print('❌ Missing sessionId or action');
          }
        } else {
          print('❌ No arguments received or invalid format');
        }
      } catch (e, stackTrace) {
        print('❌ Error handling notification action: $e');
        print('Stack trace: $stackTrace');
      }
    }
  });
  print('🔔 Native notification action handler initialized!');

  print('✓ Running app...');
  runApp(const ProviderScope(child: FlowApp()));
}

const kAccentGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color.fromRGBO(10, 172, 223, 1), // sky blue
    Color.fromRGBO(73, 191, 195, 1), // aqua green
  ],
);

class FlowApp extends StatefulWidget {
  const FlowApp({super.key});

  @override
  State<FlowApp> createState() => _FlowAppState();
}

class _FlowAppState extends State<FlowApp> {
  late final GoRouter _router;
  
  @override
  void initState() {
    super.initState();
    _setupRouter();
    _checkForNotificationIntent();
  }
  
  void _setupRouter() {
    _router = GoRouter(
      initialLocation: '/welcome',
      refreshListenable: GoRouterRefreshStream(FirebaseAuth.instance.authStateChanges()),
      redirect: (context, state) {
        final loggedIn = FirebaseAuth.instance.currentUser != null;
        final path = state.uri.path;
        final goingToAuth = path == '/auth' || path == '/welcome';
        if (!loggedIn && !goingToAuth) return '/auth';
        if (loggedIn && (path == '/auth' || path == '/welcome' || path == '/')) return '/home';
        return null;
      },
      routes: [
        GoRoute(
          path: '/welcome',
          builder: (context, state) => OnboardingScreen(),
        ),
        GoRoute(
          path: '/auth',
          builder: (context, state) => AuthScreen(),
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) => const HomeScreen(),
          routes: [
            GoRoute(
              path: 'settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
        GoRoute(
          path: '/in-session',
          builder: (context, state) => const InSessionScreen(),
        ),
        GoRoute(
          path: '/history',
          builder: (context, state) => const HistoryScreen(),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/advanced-settings',
          builder: (context, state) => const AdvancedSettingsScreen(),
        ),
        GoRoute(
          path: '/sprints',
          builder: (context, state) {
            final fromNotification = state.uri.queryParameters['fromNotification'] == 'true';
            final sessionId = state.uri.queryParameters['sessionId'];
            final preCreatedSprintId = state.uri.queryParameters['preCreatedSprintId'];
            
            if (fromNotification && _pendingNotificationSession != null) {
              final session = _pendingNotificationSession!;
              _pendingNotificationSession = null; // Clear after use
              
              return SprintGoalsScreen(
                scheduledSession: session,
                preCreatedSprintId: preCreatedSprintId,
              );
            }
            
            return const SprintGoalsScreen();
          },
        ),
        GoRoute(
          path: '/sprint-preview',
          builder: (context, state) {
            final sessionId = state.uri.queryParameters['sessionId'] ?? '';
            final preCreatedSprintId = state.uri.queryParameters['preCreatedSprintId'];
            
            // Use pending session data if available
            if (_pendingNotificationSession != null) {
              final session = _pendingNotificationSession!;
              _pendingNotificationSession = null; // Clear after use
              
              return SprintPreviewScreen(
                scheduledSession: session,
                preCreatedSprintId: preCreatedSprintId,
              );
            }
            
            // Fallback: try to fetch session by ID
            return FutureBuilder<ScheduledSession?>(
              future: sessionId.isNotEmpty ? _fetchSession(sessionId, FirebaseAuth.instance.currentUser?.uid ?? '') : Future.value(null),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    backgroundColor: Color(0xFF000000),
                    body: Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                
                final session = snapshot.data;
                if (session == null) {
                  return Scaffold(
                    backgroundColor: const Color(0xFF000000),
                    appBar: AppBar(
                      backgroundColor: const Color(0xFF000000),
                      title: const Text('Error'),
                    ),
                    body: const Center(
                      child: Text(
                        'Session not found',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  );
                }
                
                return SprintPreviewScreen(
                  scheduledSession: session,
                  preCreatedSprintId: preCreatedSprintId,
                );
              },
            );
          },
        ),
        GoRoute(
          path: '/sprint-timer',
          builder: (context, state) {
            final goalName = state.uri.queryParameters['goalName'] ?? '';
            final sprintName = state.uri.queryParameters['sprintName'] ?? '';
            final durationMinutes = int.tryParse(state.uri.queryParameters['durationMinutes'] ?? '25') ?? 25;
            final sprintIndex = int.tryParse(state.uri.queryParameters['sprintIndex'] ?? '0') ?? 0;
            final phase = state.uri.queryParameters['phase'] ?? 'sprint';
            final preCreatedSprintId = state.uri.queryParameters['preCreatedSprintId'];
            final fromNotification = state.uri.queryParameters['fromNotification'] == 'true';
            
            print('🔍 Sprint timer route - goalName=$goalName, sprintName=$sprintName, durationMinutes=$durationMinutes, sprintIndex=$sprintIndex, preCreatedSprintId=$preCreatedSprintId, fromNotification=$fromNotification');
            
            return SprintTimerScreen(
              goalName: goalName,
              sprintName: sprintName,
              durationMinutes: durationMinutes,
              sprintIndex: sprintIndex,
              preCreatedSprintId: preCreatedSprintId,
            );
          },
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/leaderboard',
          builder: (context, state) => const LeaderboardScreen(),
        ),
        GoRoute(
          path: '/sounds',
          builder: (context, state) => const SoundsScreen(),
        ),
        GoRoute(
          path: '/planner',
          builder: (context, state) => const PlannerScreen(),
        ),
        GoRoute(
          path: '/app-blocking',
          builder: (context, state) => AppBlockingScreen(),
        ),
      ],
    );
    
    // Store router globally for notification navigation
    _globalRouter = _router;
  }
  
  void _checkForNotificationIntent() {
    // Check for notification intent to open app blocking
    // This will be called when the app starts
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // You can add platform channel here to check for notification intent
      // For now, we'll handle it through deep links when the notification is clicked
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF000000),
        primaryColor: const Color.fromRGBO(10, 172, 223, 1),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromRGBO(10, 172, 223, 1),
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF000000),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: Colors.white),
          bodyMedium: TextStyle(fontSize: 16, color: Colors.white),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            padding: MaterialStateProperty.all(EdgeInsets.symmetric(vertical: 12)),
            shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            backgroundColor: MaterialStateProperty.resolveWith<Color?>((states) => null), // Use gradient in button widget
          ),
        ),
      ),
      builder: (context, child) => child ?? const SizedBox.shrink(),
      debugShowCheckedModeBanner: false,
    );
  }
}
