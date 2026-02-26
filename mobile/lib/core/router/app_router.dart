import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_notifier.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/workout/presentation/screens/timer_screen.dart';
import '../../features/workout/presentation/screens/workout_editor_screen.dart';

// Bridges AuthNotifier (a ChangeNotifier) to GoRouter's refreshListenable.
// GoRouter calls the redirect callback whenever this notifier fires,
// re-evaluating whether the current route is still allowed.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(AuthNotifier authNotifier) {
    authNotifier.addListener(notifyListeners);
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  // Keep a reference so the notifier isn't garbage-collected
  final authNotifier = ref.watch(authProvider);
  final refreshNotifier = _RouterRefreshNotifier(authNotifier);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final status = authNotifier.state.status;

      // Still checking stored credentials — don't redirect yet
      if (status == AuthStatus.initial) return null;

      final isAuthenticated = status == AuthStatus.authenticated;
      final location = state.matchedLocation;
      final isOnAuthRoute = location == '/login' || location == '/register';

      if (!isAuthenticated && !isOnAuthRoute) return '/login';
      if (isAuthenticated && isOnAuthRoute) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (_, state) => _HomeScreen(),
      ),
      GoRoute(
        path: '/timer',
        builder: (_, state) {
          final workout = state.extra as Workout?;
          return TimerScreen(workout: workout);
        },
      ),
      GoRoute(
        path: '/editor',
        builder: (_, __) => const WorkoutEditorScreen(),
      ),
    ],
  );
});

// Placeholder home screen — replace with your actual home feature
class _HomeScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider).logout(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Welcome!'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => context.go('/editor'),
              child: const Text('New workout'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => context.go('/timer'),
              child: const Text('Quick start'),
            ),
          ],
        ),
      ),
    );
  }
}
