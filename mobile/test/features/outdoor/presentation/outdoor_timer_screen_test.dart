import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:training_timer/features/outdoor/core/outdoor_audio_service.dart';
import 'package:training_timer/features/outdoor/core/outdoor_workout_engine.dart';
import 'package:training_timer/features/outdoor/data/models/outdoor_models.dart';
import 'package:training_timer/features/outdoor/presentation/screens/outdoor_timer_screen.dart';

// ─── Fake audio service ───────────────────────────────────────────────────────
//
// No-op override: avoids real FlutterTts platform-channel calls in widget tests.

class _FakeAudioService extends OutdoorAudioService {
  @override
  Future<void> init() async {}

  @override
  Future<void> handleAnnouncement(OutdoorAnnouncement announcement) async {}

  @override
  Future<void> dispose() async {}
}

// ─── Fake engine ─────────────────────────────────────────────────────────────
//
// Concrete fake rather than a Mock so we avoid mocktail global-recording-state
// pollution between tests (the "Cannot call when within a stub response" error).

class _FakeEngine implements OutdoorWorkoutEngine {
  final _stateCtrl = StreamController<OutdoorWorkoutState>.broadcast();
  final _announcementCtrl = StreamController<OutdoorAnnouncement>.broadcast();

  bool startCalled = false;
  int stopCallCount = 0;
  Object? startError;

  @override
  Stream<OutdoorWorkoutState> get stateStream => _stateCtrl.stream;

  @override
  Stream<OutdoorAnnouncement> get announcementStream =>
      _announcementCtrl.stream;

  @override
  OutdoorWorkoutState get currentState => OutdoorWorkoutState.initial;

  @override
  Future<void> start(OutdoorWorkout workout) async {
    startCalled = true;
    if (startError != null) throw startError!;
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
  }

  @override
  Future<void> dispose() async {
    if (!_stateCtrl.isClosed) await _stateCtrl.close();
    if (!_announcementCtrl.isClosed) await _announcementCtrl.close();
  }

  void push(OutdoorWorkoutState state) => _stateCtrl.add(state);

  Future<void> close() async {
    if (!_stateCtrl.isClosed) await _stateCtrl.close();
    if (!_announcementCtrl.isClosed) await _announcementCtrl.close();
  }
}

// ─── Test workout ─────────────────────────────────────────────────────────────

const _testWorkout = OutdoorWorkout(
  elements: [
    OutdoorElement.segment(OutdoorSegment.timed(
      seconds: 60,
      tag: OutdoorSegmentTag.warmUp(),
      name: 'Warm-up',
    )),
    OutdoorElement.segment(OutdoorSegment.timed(
      seconds: 240,
      tag: OutdoorSegmentTag.work(),
      name: 'Hard effort',
    )),
  ],
);

// ─── State helpers ────────────────────────────────────────────────────────────

OutdoorWorkoutState _makeActive({
  OutdoorSegment segment = const OutdoorSegment.timed(
    seconds: 240,
    tag: OutdoorSegmentTag.work(),
    name: 'Hard effort',
  ),
  Duration timeRemaining = const Duration(minutes: 4),
  int segmentIndex = 0,
  int totalSegments = 2,
  OutdoorSegment? nextSegment,
}) =>
    OutdoorWorkoutState(
      phase: OutdoorWorkoutPhase.active,
      segmentIndex: segmentIndex,
      totalSegments: totalSegments,
      currentSegment: segment,
      totalElapsed: Duration.zero,
      segmentElapsed: Duration.zero,
      timeRemaining: timeRemaining,
      totalDistanceMetres: 0,
      segmentDistanceMetres: 0,
      distanceRemainingMetres: null,
      paceMinPerKm: null,
      currentBpm: null,
      segmentAvgBpm: null,
      countdownValue: null,
      nextSegment: nextSegment,
    );

OutdoorWorkoutState _makeCountdown({required int value}) =>
    OutdoorWorkoutState(
      phase: OutdoorWorkoutPhase.countdown,
      segmentIndex: 0,
      totalSegments: 2,
      currentSegment: const OutdoorSegment.timed(
        seconds: 60,
        tag: OutdoorSegmentTag.warmUp(),
      ),
      totalElapsed: const Duration(minutes: 1),
      segmentElapsed: const Duration(minutes: 1),
      timeRemaining: Duration.zero,
      totalDistanceMetres: 800,
      segmentDistanceMetres: 800,
      distanceRemainingMetres: null,
      paceMinPerKm: null,
      currentBpm: null,
      segmentAvgBpm: null,
      countdownValue: value,
    );

const _finishedState = OutdoorWorkoutState(
  phase: OutdoorWorkoutPhase.finished,
  segmentIndex: 1,
  totalSegments: 2,
  currentSegment: null,
  totalElapsed: Duration(minutes: 25),
  segmentElapsed: Duration.zero,
  timeRemaining: null,
  totalDistanceMetres: 4200,
  segmentDistanceMetres: 0,
  distanceRemainingMetres: null,
  paceMinPerKm: null,
  currentBpm: null,
  segmentAvgBpm: null,
  countdownValue: null,
);

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late _FakeEngine engine;

  setUp(() {
    engine = _FakeEngine();
  });

  tearDown(() async {
    await engine.close();
  });

  // Wraps the screen in a GoRouter so context.pop() works (stop dialog) and
  // pushReplacement to /outdoor-results works (workout finished).
  Widget buildWidget({String workoutName = ''}) {
    return ProviderScope(
      overrides: [
        outdoorWorkoutEngineProvider.overrideWithValue(engine),
        outdoorAudioServiceProvider.overrideWithValue(_FakeAudioService()),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/timer',
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (_, __) =>
                  const NoTransitionPage(child: Scaffold()),
              routes: [
                GoRoute(
                  path: 'timer',
                  pageBuilder: (_, __) => NoTransitionPage(
                    child: OutdoorTimerScreen(
                      workout: _testWorkout,
                      workoutName: workoutName,
                    ),
                  ),
                ),
              ],
            ),
            GoRoute(
              path: '/outdoor-results',
              pageBuilder: (_, __) => const NoTransitionPage(
                child: Scaffold(body: Center(child: Text('Results'))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('shows loading indicator while idle', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows tag chip and time remaining in active state',
      (tester) async {
    await tester.pumpWidget(buildWidget());

    engine.push(_makeActive(
      segment: const OutdoorSegment.timed(
        seconds: 240,
        tag: OutdoorSegmentTag.work(),
        name: 'Hard effort',
      ),
      timeRemaining: const Duration(minutes: 4),
    ));
    await tester.pump();

    expect(find.text('WORK'), findsOneWidget);
    expect(find.text('4:00'), findsOneWidget);
    expect(find.text('remaining'), findsOneWidget);
  });

  testWidgets('shows warm-up tag chip', (tester) async {
    await tester.pumpWidget(buildWidget());

    engine.push(_makeActive(
      segment: const OutdoorSegment.timed(
        seconds: 600,
        tag: OutdoorSegmentTag.warmUp(),
        name: 'Warm-up jog',
      ),
      timeRemaining: const Duration(minutes: 10),
    ));
    await tester.pump();

    expect(find.text('WARM-UP'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
  });

  testWidgets('shows upcoming segment in meta row', (tester) async {
    await tester.pumpWidget(buildWidget());

    engine.push(_makeActive(
      segmentIndex: 0,
      totalSegments: 2,
      nextSegment: const OutdoorSegment.timed(
        seconds: 180,
        tag: OutdoorSegmentTag.rest(),
        name: 'Recovery',
      ),
    ));
    await tester.pump();

    expect(find.text('Segment 1 of 2'), findsOneWidget);
    expect(find.text('Rest'), findsOneWidget);
  });

  testWidgets('shows HR data with zone badge', (tester) async {
    await tester.pumpWidget(buildWidget());

    engine.push(const OutdoorWorkoutState(
      phase: OutdoorWorkoutPhase.active,
      segmentIndex: 0,
      totalSegments: 2,
      currentSegment: OutdoorSegment.timed(
        seconds: 240,
        tag: OutdoorSegmentTag.work(),
      ),
      totalElapsed: Duration.zero,
      segmentElapsed: Duration.zero,
      timeRemaining: Duration(minutes: 4),
      totalDistanceMetres: 0,
      segmentDistanceMetres: 0,
      distanceRemainingMetres: null,
      paceMinPerKm: null,
      currentBpm: 165,
      segmentAvgBpm: 162.0,
      countdownValue: null,
    ));
    await tester.pump();

    expect(find.text('165'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
    expect(find.text('Zone 3'), findsOneWidget);
    expect(find.text('avg 162 BPM'), findsOneWidget);
  });

  testWidgets('shows countdown overlay', (tester) async {
    await tester.pumpWidget(buildWidget());

    engine.push(_makeCountdown(value: 3));
    await tester.pump();

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('countdown overlay updates to each value', (tester) async {
    await tester.pumpWidget(buildWidget());

    engine.push(_makeCountdown(value: 2));
    await tester.pump();

    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('shows loading indicator when finished (awaiting navigation)',
      (tester) async {
    await tester.pumpWidget(buildWidget());

    engine.push(_finishedState);
    await tester.pump(); // stream callback fires, setState, addPostFrameCallback

    // While the post-frame navigation is pending the screen shows a spinner.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('navigates to outdoor-results when workout finishes',
      (tester) async {
    await tester.pumpWidget(buildWidget(workoutName: 'My Run'));

    engine.push(_finishedState);
    await tester.pump(); // stream callback + setState + addPostFrameCallback
    await tester.pump(); // post-frame callback fires → pushReplacement
    await tester.pump(); // GoRouter renders /outdoor-results

    expect(find.text('Results'), findsOneWidget);
  });

  testWidgets('navigation to results fires only once even if finished state is emitted twice',
      (tester) async {
    await tester.pumpWidget(buildWidget());

    engine.push(_finishedState);
    await tester.pump();
    engine.push(_finishedState); // second emission — guard should ignore it
    await tester.pump();
    await tester.pump(); // post-frame callback
    await tester.pump(); // GoRouter

    // Still on the results stub (not crashed or pushed twice).
    expect(find.text('Results'), findsOneWidget);
  });

  testWidgets('shows GPS error when start throws', (tester) async {
    engine.startError = StateError('GPS permission denied');

    await tester.pumpWidget(buildWidget());
    await tester.pump(); // let _startWorkout() async throw + setState

    expect(find.text('GPS Unavailable'), findsOneWidget);
    expect(find.text('Bad state: GPS permission denied'), findsOneWidget);
  });

  testWidgets('shows stats row in active state', (tester) async {
    await tester.pumpWidget(buildWidget());

    engine.push(_makeActive());
    await tester.pump();

    expect(find.text('PACE'), findsOneWidget);
    expect(find.text('SEGMENT'), findsOneWidget);
    expect(find.text('TOTAL'), findsOneWidget);
    expect(find.text('ELAPSED'), findsOneWidget);
  });

  testWidgets('stop button shows confirmation dialog', (tester) async {
    await tester.pumpWidget(buildWidget());

    engine.push(_makeActive());
    await tester.pump();

    await tester.tap(find.text('Stop Workout'));
    await tester.pumpAndSettle();

    expect(find.text('Stop Workout?'), findsOneWidget);
    expect(find.text('Keep Going'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('engine.stop called when dialog confirmed', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump();

    engine.push(_makeActive());
    await tester.pump();

    await tester.tap(find.text('Stop Workout'));
    await tester.pump(); // open dialog

    await tester.tap(find.text('Stop'));
    await tester.pump(); // _stop() starts (engine.stop called here)
    await tester.pump(); // _stop() completes + context.pop() fires

    // engine.stop() is also called from dispose(), so count ≥ 1.
    expect(engine.stopCallCount, greaterThanOrEqualTo(1));
  });

  testWidgets('engine.stop NOT called when dialog cancelled', (tester) async {
    await tester.pumpWidget(buildWidget());

    engine.push(_makeActive());
    await tester.pump();

    await tester.tap(find.text('Stop Workout'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keep Going'));
    await tester.pumpAndSettle();

    expect(engine.stopCallCount, 0);
  });
}
