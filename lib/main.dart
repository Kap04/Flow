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
import 'leaderboard_screen.dart';
import 'sounds_screen.dart';
import 'profile_screen.dart';
import 'notification_service.dart';
import 'advanced_settings_screen.dart';

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  await Firebase.initializeApp();
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

class FlowApp extends StatelessWidget {
  const FlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    final _router = GoRouter(
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
          builder: (context, state) => const SprintGoalsScreen(),
        ),
        GoRoute(
          path: '/sprint-timer',
          builder: (context, state) {
            final goalName = state.uri.queryParameters['goalName'] ?? '';
            final sprintName = state.uri.queryParameters['sprintName'] ?? '';
            final durationMinutes = int.tryParse(state.uri.queryParameters['durationMinutes'] ?? '25') ?? 25;
            final sprintIndex = int.tryParse(state.uri.queryParameters['sprintIndex'] ?? '0') ?? 0;
            final phase = state.uri.queryParameters['phase'] ?? 'sprint';
            print('🔍 Route received: goalName=$goalName, sprintName=$sprintName, durationMinutes=$durationMinutes, sprintIndex=$sprintIndex, phase=$phase');
            return SprintTimerScreen(
              goalName: goalName,
              sprintName: sprintName,
              durationMinutes: durationMinutes,
              sprintIndex: sprintIndex,
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
      ],
    );
    return MaterialApp.router(
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
  // Use explicit router delegates from GoRouter so we can provide a
  // backButtonDispatcher. Some Flutter versions assert when
  // `routerConfig` is used together with other router delegates.
  routeInformationProvider: _router.routeInformationProvider,
  routeInformationParser: _router.routeInformationParser,
  routerDelegate: _router.routerDelegate,
  backButtonDispatcher: RootBackButtonDispatcher(),
      builder: (context, child) => child ?? const SizedBox.shrink(),
      debugShowCheckedModeBanner: false,
    );
  }
}
