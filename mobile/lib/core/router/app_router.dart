import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_notifier.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/outdoor/data/models/outdoor_models.dart';
import '../../features/outdoor/data/models/outdoor_history_models.dart';
import '../../features/outdoor/presentation/screens/hr_connect_screen.dart';
import '../../features/outdoor/presentation/screens/outdoor_editor_screen.dart';
import '../../features/outdoor/presentation/screens/outdoor_home_screen.dart';
import '../../features/outdoor/presentation/screens/outdoor_results_screen.dart';
import '../../features/outdoor/presentation/screens/outdoor_timer_screen.dart';
import '../../features/workout/data/models/workout_models.dart';
import '../../features/workout/presentation/screens/my_workouts_screen.dart';
import '../../features/workout/presentation/screens/timer_screen.dart';
import '../../features/workout/presentation/screens/workout_editor_screen.dart';
import '../navigation/main_shell.dart';

// Bridges AuthNotifier (a ChangeNotifier) to GoRouter's refreshListenable.
// GoRouter calls the redirect callback whenever this notifier fires,
// re-evaluating whether the current route is still allowed.
class _RouterRefreshNotifier extends ChangeNotifier {
  late final VoidCallback _listener;
  final AuthNotifier authNotifier;

  _RouterRefreshNotifier(this.authNotifier) {
    _listener = notifyListeners;
    authNotifier.addListener(_listener);
  }

  @override
  void dispose() {
    authNotifier.removeListener(_listener);
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  // Keep a reference so the notifier isn't garbage-collected.
  final authNotifier = ref.watch(authProvider);
  final refreshNotifier = _RouterRefreshNotifier(authNotifier);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final status = authNotifier.state.status;

      // Still checking stored credentials — don't redirect yet.
      if (status == AuthStatus.initial) return null;

      final isAuthenticated = status == AuthStatus.authenticated;
      final location = state.matchedLocation;
      final isOnAuthRoute = location == '/login' || location == '/register';

      if (!isAuthenticated && !isOnAuthRoute) return '/login';
      if (isAuthenticated && isOnAuthRoute) return '/home';
      return null;
    },
    routes: [
      // ── Auth routes (no shell, no bottom nav) ─────────────────────────────
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (_, __) => const RegisterScreen(),
      ),

      // ── Main shell: two top-level sections with independent nav stacks ────
      StatefulShellRoute.indexedStack(
        builder: (_, __, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          // Branch 0 — Gym Timer
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, __) => const MyWorkoutsScreen(),
              ),
            ],
          ),
          // Branch 1 — Outdoor Training
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/outdoor',
                builder: (_, __) => const OutdoorHomeScreen(),
              ),
            ],
          ),
        ],
      ),

      // ── Full-screen routes (push on top of shell, no bottom nav) ──────────
      GoRoute(
        path: '/timer',
        builder: (_, state) {
          final preset = state.extra as WorkoutPreset?;
          return TimerScreen(preset: preset);
        },
      ),
      GoRoute(
        path: '/editor',
        builder: (_, state) {
          final preset = state.extra as WorkoutPreset?;
          return WorkoutEditorScreen(initialPreset: preset);
        },
      ),
      GoRoute(
        path: '/hr-connect',
        builder: (_, __) => const HrConnectScreen(),
      ),
      GoRoute(
        path: '/outdoor-editor',
        builder: (_, state) {
          final preset = state.extra as OutdoorWorkoutPreset?;
          return OutdoorEditorScreen(initialPreset: preset);
        },
      ),
      GoRoute(
        path: '/outdoor-timer',
        builder: (_, state) {
          final args =
              state.extra! as ({OutdoorWorkout workout, String name});
          return OutdoorTimerScreen(
              workout: args.workout, workoutName: args.name);
        },
      ),
      GoRoute(
        path: '/outdoor-results',
        builder: (_, state) {
          final entry = state.extra! as OutdoorWorkoutHistoryEntry;
          return OutdoorResultsScreen(entry: entry);
        },
      ),
    ],
  );
});
