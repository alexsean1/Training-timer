import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/auth/presentation/auth_notifier.dart';
import 'package:mobile/features/auth/presentation/screens/login_screen.dart';

import '../../../helpers/test_helpers.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

Widget _buildLoginScreen({FakeAuthNotifier? notifier}) {
  final fake = notifier ?? FakeAuthNotifier();
  return ProviderScope(
    overrides: [authProvider.overrideWith((ref) => fake)],
    child: const MaterialApp(home: LoginScreen()),
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('LoginScreen — rendering', () {
    testWidgets('shows email field, password field, and sign-in button',
        (tester) async {
      await tester.pumpWidget(_buildLoginScreen());

      expect(find.byType(TextFormField), findsNWidgets(2));
      // The heading and the button both say "Sign In":
      expect(find.text('Sign In'), findsWidgets);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('shows "Don\'t have an account?" link', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());

      expect(find.text("Don't have an account? Sign Up"), findsOneWidget);
    });
  });

  group('LoginScreen — form validation', () {
    testWidgets('shows required errors when submitted with empty fields',
        (tester) async {
      await tester.pumpWidget(_buildLoginScreen());

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('shows invalid email error for bad email format',
        (tester) async {
      await tester.pumpWidget(_buildLoginScreen());

      await tester.enterText(
          find.byType(TextFormField).first, 'notanemail');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(find.text('Enter a valid email address'), findsOneWidget);
    });

    testWidgets('shows short password error when password < 8 chars',
        (tester) async {
      await tester.pumpWidget(_buildLoginScreen());

      await tester.enterText(
          find.byType(TextFormField).first, 'user@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'short');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    });

    testWidgets('does not show errors for valid email and password',
        (tester) async {
      await tester.pumpWidget(_buildLoginScreen());

      await tester.enterText(
          find.byType(TextFormField).first, 'user@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(find.text('Email is required'), findsNothing);
      expect(find.text('Password is required'), findsNothing);
      expect(find.text('Enter a valid email address'), findsNothing);
      expect(find.text('Password must be at least 8 characters'), findsNothing);
    });
  });

  group('LoginScreen — loading state', () {
    testWidgets('disables button and shows spinner when status is loading',
        (tester) async {
      final notifier = FakeAuthNotifier(
        initialState: const AuthState(status: AuthStatus.loading),
      );
      await tester.pumpWidget(_buildLoginScreen(notifier: notifier));

      final button =
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull,
          reason: 'Button must be disabled while loading');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('re-enables button when loading finishes', (tester) async {
      final notifier = FakeAuthNotifier(
        initialState: const AuthState(status: AuthStatus.loading),
      );
      await tester.pumpWidget(_buildLoginScreen(notifier: notifier));

      notifier.setStatus(AuthStatus.unauthenticated);
      await tester.pump();

      final button =
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('LoginScreen — error display', () {
    testWidgets('shows error message from auth state', (tester) async {
      final notifier = FakeAuthNotifier(
        initialState: const AuthState(
          status: AuthStatus.unauthenticated,
          error: 'Invalid credentials',
        ),
      );
      await tester.pumpWidget(_buildLoginScreen(notifier: notifier));

      expect(find.text('Invalid credentials'), findsOneWidget);
    });

    testWidgets('clears error message when it is null', (tester) async {
      final notifier = FakeAuthNotifier(
        initialState: const AuthState(
          status: AuthStatus.unauthenticated,
          error: null,
        ),
      );
      await tester.pumpWidget(_buildLoginScreen(notifier: notifier));

      // No stray error text visible
      expect(find.text('Invalid credentials'), findsNothing);
    });
  });

  group('LoginScreen — submit behaviour', () {
    testWidgets('calls notifier.login with correct email and password',
        (tester) async {
      final notifier = FakeAuthNotifier();
      await tester.pumpWidget(_buildLoginScreen(notifier: notifier));

      await tester.enterText(
          find.byType(TextFormField).first, 'user@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(notifier.loginCalls, hasLength(1));
      expect(notifier.loginCalls.first.email, 'user@example.com');
      expect(notifier.loginCalls.first.password, 'password123');
    });

    testWidgets('does not call login when form is invalid', (tester) async {
      final notifier = FakeAuthNotifier();
      await tester.pumpWidget(_buildLoginScreen(notifier: notifier));

      // Tap without filling in any fields
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(notifier.loginCalls, isEmpty);
    });

    testWidgets('email is trimmed before calling login', (tester) async {
      final notifier = FakeAuthNotifier();
      await tester.pumpWidget(_buildLoginScreen(notifier: notifier));

      await tester.enterText(
          find.byType(TextFormField).first, '  user@example.com  ');
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(notifier.loginCalls, hasLength(1));
      expect(notifier.loginCalls.first.email, 'user@example.com');
    });
  });
}
