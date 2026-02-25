/// Top-level smoke test: verifies that [FakeAuthNotifier] integrates
/// with Riverpod correctly and that provider overrides work as expected.
///
/// More detailed widget tests live in
/// `test/features/auth/presentation/login_screen_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:training_timer/features/auth/presentation/auth_notifier.dart';

import 'helpers/test_helpers.dart';

void main() {
  testWidgets(
      'FakeAuthNotifier: unauthenticated state is reflected in the widget tree',
      (tester) async {
    final notifier = FakeAuthNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              final status = ref.watch(authProvider).state.status;
              return Scaffold(
                body: Text(
                  status == AuthStatus.unauthenticated ? 'Sign in' : 'Home',
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('FakeAuthNotifier.setStatus rebuilds listeners', (tester) async {
    final notifier = FakeAuthNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              final status = ref.watch(authProvider).state.status;
              return Scaffold(
                body: Text(
                  status == AuthStatus.authenticated ? 'Welcome' : 'Sign in',
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Sign in'), findsOneWidget);

    notifier.setStatus(AuthStatus.authenticated);
    await tester.pump();

    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('buildTestApp helper wraps widget in ProviderScope + MaterialApp',
      (tester) async {
    await tester.pumpWidget(
      buildTestApp(
        const Text('Hello from buildTestApp'),
      ),
    );

    expect(find.text('Hello from buildTestApp'), findsOneWidget);
  });
}
