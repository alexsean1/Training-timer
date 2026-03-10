import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:training_timer/features/workout/data/models/workout_history.dart';
import 'package:training_timer/features/workout/data/models/workout_models.dart';
import 'package:training_timer/features/workout/data/repositories/workout_history_repository.dart';
import 'package:training_timer/features/workout/presentation/screens/timer_screen.dart';
import 'package:training_timer/features/workout/presentation/screens/workout_editor_screen.dart';

// ── Fake history repository ────────────────────────────────────────────────────

class _FakeHistoryRepo implements WorkoutHistoryRepository {
  @override
  Future<List<WorkoutHistoryEntry>> getAll() async => [];

  @override
  Future<void> add(WorkoutHistoryEntry entry) async {}

  @override
  Future<void> clear() async {}
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _buildApp() {
  final router = GoRouter(
    initialLocation: '/editor',
    routes: [
      GoRoute(
        path: '/editor',
        builder: (_, __) => const WorkoutEditorScreen(),
      ),
      GoRoute(
        path: '/timer',
        builder: (_, state) {
          final preset = state.extra as WorkoutPreset?;
          return ProviderScope(
            overrides: [
              workoutHistoryRepositoryProvider
                  .overrideWithValue(_FakeHistoryRepo()),
            ],
            child: TimerScreen(preset: preset),
          );
        },
      ),
    ],
  );
  return ProviderScope(child: MaterialApp.router(routerConfig: router));
}

/// Builds an app where `/` → `/editor` so back-navigation is possible.
Widget _buildAppWithBack() {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('Home')),
        routes: [
          GoRoute(
            path: 'editor',
            builder: (_, __) => const WorkoutEditorScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/timer',
        builder: (_, state) {
          final preset = state.extra as WorkoutPreset?;
          return ProviderScope(
            overrides: [
              workoutHistoryRepositoryProvider
                  .overrideWithValue(_FakeHistoryRepo()),
            ],
            child: TimerScreen(preset: preset),
          );
        },
      ),
    ],
  );
  return ProviderScope(child: MaterialApp.router(routerConfig: router));
}

/// Adds one segment via the UI.
Future<void> _addSegment(
  WidgetTester tester, {
  String type = 'EMOM',
  String minutes = '2',
  String seconds = '00',
}) async {
  // "Add Segment" may be a FilledButton (empty state) or OutlinedButton (bottom bar)
  final filled = find.widgetWithText(FilledButton, 'Add Segment');
  final outlined = find.widgetWithText(OutlinedButton, 'Add Segment');
  if (filled.evaluate().isNotEmpty) {
    await tester.tap(filled.first);
  } else {
    await tester.tap(outlined.first);
  }
  await tester.pumpAndSettle();

  // Each row has both a chip and a title — match the ListTile to avoid ambiguity
  await tester.tap(find.widgetWithText(ListTile, type).first);
  await tester.pumpAndSettle();

  await tester.enterText(find.widgetWithText(TextFormField, 'Min'), minutes);
  await tester.enterText(find.widgetWithText(TextFormField, 'Sec'), seconds);

  await tester.tap(find.widgetWithText(FilledButton, 'Add'));
  await tester.pumpAndSettle();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('WorkoutEditorScreen', () {
    testWidgets('renders empty state with name field and Add Segment button',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Workout name (optional)'), findsOneWidget);
      expect(find.text('No segments yet'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add Segment'), findsOneWidget);
    });

    testWidgets('bottom bar appears after adding a segment', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await _addSegment(tester, type: 'EMOM', minutes: '5', seconds: '00');

      expect(
          find.widgetWithText(OutlinedButton, 'Add Segment'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Start Workout'), findsOneWidget);
    });

    testWidgets('adds EMOM segment and shows chip + duration', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await _addSegment(tester, type: 'EMOM', minutes: '2', seconds: '00');

      expect(find.text('EMOM'), findsOneWidget);
      expect(find.text('02:00'), findsOneWidget);
    });

    testWidgets('adds REST segment', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await _addSegment(tester, type: 'REST', minutes: '1', seconds: '30');

      expect(find.text('REST'), findsOneWidget);
      expect(find.text('01:30'), findsOneWidget);
    });

    testWidgets('adds AMRAP segment', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await _addSegment(tester, type: 'AMRAP', minutes: '10', seconds: '00');

      expect(find.text('AMRAP'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);
    });

    testWidgets('adds FOR TIME segment', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await _addSegment(
          tester, type: 'FOR TIME', minutes: '0', seconds: '45');

      expect(find.text('FOR TIME'), findsOneWidget);
      expect(find.text('00:45'), findsOneWidget);
    });

    testWidgets('Start Workout navigates to timer screen', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await _addSegment(tester, type: 'AMRAP', minutes: '3', seconds: '00');

      await tester.tap(find.widgetWithText(FilledButton, 'Start Workout'));
      await tester.pumpAndSettle();

      expect(find.text('Workout Timer'), findsOneWidget);
    });

    testWidgets('can edit an existing segment', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await _addSegment(tester, type: 'EMOM', minutes: '5', seconds: '00');
      expect(find.text('05:00'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Min'), '10');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('10:00'), findsOneWidget);
      expect(find.text('05:00'), findsNothing);
    });

    testWidgets('can delete a segment by swiping', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await _addSegment(tester, type: 'REST', minutes: '1', seconds: '00');
      expect(find.text('REST'), findsOneWidget);

      await tester.drag(
          find.byType(Dismissible).first, const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.text('REST'), findsNothing);
      expect(find.text('No segments yet'), findsOneWidget);
    });

    testWidgets('groups two adjacent segments into a group card',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await _addSegment(tester, type: 'EMOM', minutes: '3', seconds: '00');
      await _addSegment(tester, type: 'REST', minutes: '1', seconds: '00');

      // Long-press first card to enter selection mode
      await tester.longPress(find.text('03:00'));
      await tester.pumpAndSettle();

      // Tap second card to add to selection
      await tester.tap(find.text('01:00'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Group 2 selected'),
          findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Group 2 selected'));
      await tester.pumpAndSettle();

      // Repeat count dialog
      expect(find.text('Repeat group'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Group'));
      await tester.pumpAndSettle();

      expect(find.textContaining('GROUP ×'), findsOneWidget);
    });

    testWidgets('can update group repeat count via edit sheet', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await _addSegment(tester, type: 'EMOM', minutes: '3', seconds: '00');
      await _addSegment(tester, type: 'REST', minutes: '1', seconds: '00');

      await tester.longPress(find.text('03:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('01:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Group 2 selected'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Group'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Edit group'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Repeats'), '5');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('GROUP × 5'), findsOneWidget);
    });

    testWidgets('can ungroup', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await _addSegment(tester, type: 'EMOM', minutes: '3', seconds: '00');
      await _addSegment(tester, type: 'REST', minutes: '1', seconds: '00');

      await tester.longPress(find.text('03:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('01:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Group 2 selected'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Group'));
      await tester.pumpAndSettle();

      expect(find.textContaining('GROUP ×'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Ungroup'));
      await tester.pumpAndSettle();

      expect(find.textContaining('GROUP ×'), findsNothing);
      expect(find.text('EMOM'), findsOneWidget);
      expect(find.text('REST'), findsOneWidget);
    });
  });

  // ── Unsaved changes ────────────────────────────────────────────────────────

  group('unsaved changes guard', () {
    testWidgets('no dialog when back-navigating with empty editor',
        (tester) async {
      await tester.pumpWidget(_buildAppWithBack());
      await tester.pumpAndSettle();

      // Navigate to editor.
      final router = GoRouter.of(
          tester.element(find.text('Home')));
      router.push('/editor');
      await tester.pumpAndSettle();

      expect(find.text('Workout Editor'), findsOneWidget);

      // Press the AppBar back arrow — no dialog since nothing was added.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Discard changes?'), findsNothing);
    });

    testWidgets('shows discard dialog when back-navigating with a segment',
        (tester) async {
      await tester.pumpWidget(_buildAppWithBack());
      await tester.pumpAndSettle();

      final router = GoRouter.of(
          tester.element(find.text('Home')));
      router.push('/editor');
      await tester.pumpAndSettle();

      await _addSegment(tester, type: 'EMOM', minutes: '3', seconds: '00');

      // Press back — dialog should appear.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);
    });

    testWidgets('tapping Discard pops back to home', (tester) async {
      await tester.pumpWidget(_buildAppWithBack());
      await tester.pumpAndSettle();

      final router = GoRouter.of(
          tester.element(find.text('Home')));
      router.push('/editor');
      await tester.pumpAndSettle();

      await _addSegment(tester, type: 'REST', minutes: '1', seconds: '00');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // Tap Discard.
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Workout Editor'), findsNothing);
    });

    testWidgets('tapping Keep editing stays on editor', (tester) async {
      await tester.pumpWidget(_buildAppWithBack());
      await tester.pumpAndSettle();

      final router = GoRouter.of(
          tester.element(find.text('Home')));
      router.push('/editor');
      await tester.pumpAndSettle();

      await _addSegment(tester, type: 'EMOM', minutes: '2', seconds: '00');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // Tap Keep editing.
      await tester.tap(find.widgetWithText(TextButton, 'Keep editing'));
      await tester.pumpAndSettle();

      expect(find.text('Workout Editor'), findsOneWidget);
      expect(find.text('Home'), findsNothing);
    });
  });
}
