import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mobile/features/auth/presentation/auth_notifier.dart';

// ─── FakeAuthNotifier ─────────────────────────────────────────────────────────

/// A controllable stub of [AuthNotifier] for widget tests.
///
/// Extends [AuthNotifier] so it satisfies the type parameter of
/// [authProvider] (`ChangeNotifierProvider<AuthNotifier>`). Calls
/// `super.unauthenticated()` to skip secure-storage and network access
/// during construction.
///
/// Usage in widget tests:
/// ```dart
/// final fake = FakeAuthNotifier();
///
/// await tester.pumpWidget(
///   ProviderScope(
///     overrides: [authProvider.overrideWith((ref) => fake)],
///     child: const MaterialApp(home: LoginScreen()),
///   ),
/// );
///
/// // Trigger a state change and pump to rebuild:
/// fake.setStatus(AuthStatus.loading);
/// await tester.pump();
///
/// // Inspect captured calls:
/// expect(fake.loginCalls.first.email, 'user@example.com');
/// ```
class FakeAuthNotifier extends AuthNotifier {
  AuthState _fakeState;

  /// Tracks every [login] call: `(email: ..., password: ...)`.
  final List<({String email, String password})> loginCalls = [];

  /// Tracks every [register] call.
  final List<({String email, String password})> registerCalls = [];

  FakeAuthNotifier({AuthState? initialState})
      : _fakeState = initialState ??
            const AuthState(status: AuthStatus.unauthenticated),
        super.unauthenticated();

  // ─── State control ────────────────────────────────────────────────────────

  @override
  AuthState get state => _fakeState;

  /// Updates the faked state and notifies listeners (triggers widget rebuild).
  void setStatus(AuthStatus status, {String? error}) {
    _fakeState = AuthState(status: status, error: error);
    notifyListeners();
  }

  // ─── Stubbed actions ──────────────────────────────────────────────────────

  @override
  Future<void> login(String email, String password) async {
    loginCalls.add((email: email, password: password));
  }

  @override
  Future<void> register(String email, String password) async {
    registerCalls.add((email: email, password: password));
  }

  @override
  Future<void> logout() async {}
}

// ─── Widget wrapper ───────────────────────────────────────────────────────────

/// Wraps [child] in a [ProviderScope] + [MaterialApp].
///
/// Use [overrides] to replace Riverpod providers with fakes or mocks:
/// ```dart
/// buildTestApp(
///   const LoginScreen(),
///   overrides: [authProvider.overrideWith((ref) => FakeAuthNotifier())],
/// )
/// ```
Widget buildTestApp(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}
