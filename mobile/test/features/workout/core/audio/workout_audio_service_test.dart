import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:training_timer/features/workout/core/audio/audio_events.dart';
import 'package:training_timer/features/workout/core/audio/workout_audio_service.dart';

class _MockAudioPlayer extends Mock implements AudioPlayer {}

class _MockFlutterTts extends Mock implements FlutterTts {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Register fallback values for non-primitive types used with any().
    registerFallbackValue(AudioContext());
    registerFallbackValue(BytesSource(Uint8List(0)));
    registerFallbackValue(ReleaseMode.release);
  });

  late _MockAudioPlayer player;
  late _MockAudioPlayer keepalivePlayer;
  late _MockFlutterTts tts;
  late WorkoutAudioService service;

  setUp(() {
    player = _MockAudioPlayer();
    keepalivePlayer = _MockAudioPlayer();
    tts = _MockFlutterTts();
    service = WorkoutAudioService(player: player, tts: tts, keepalivePlayer: keepalivePlayer);

    when(() => player.setAudioContext(any())).thenAnswer((_) async {});
    when(() => player.play(any())).thenAnswer((_) async {});
    when(() => player.dispose()).thenAnswer((_) async {});
    when(() => keepalivePlayer.setAudioContext(any())).thenAnswer((_) async {});
    when(() => keepalivePlayer.setReleaseMode(any())).thenAnswer((_) async {});
    when(() => keepalivePlayer.play(any())).thenAnswer((_) async {});
    when(() => keepalivePlayer.stop()).thenAnswer((_) async {});
    when(() => keepalivePlayer.dispose()).thenAnswer((_) async {});
    when(() => tts.setLanguage(any())).thenAnswer((_) async => 1);
    when(() => tts.setSpeechRate(any())).thenAnswer((_) async => 1);
    when(() => tts.setVolume(any())).thenAnswer((_) async => 1);
    when(() => tts.setPitch(any())).thenAnswer((_) async => 1);
    when(() => tts.speak(any())).thenAnswer((_) async => 1);
    when(() => tts.stop()).thenAnswer((_) async => 1);
  });

  tearDown(() async => service.dispose());

  group('WorkoutAudioService', () {
    // ── init() ────────────────────────────────────────────────────────────────

    group('init()', () {
      test('configures audio context and all TTS settings', () async {
        await service.init();

        verify(() => player.setAudioContext(any())).called(1);
        verify(() => tts.setLanguage('en-US')).called(1);
        verify(() => tts.setSpeechRate(0.45)).called(1);
        verify(() => tts.setVolume(1.0)).called(1);
        verify(() => tts.setPitch(1.1)).called(1);
      });

      test('is idempotent — a second call is a no-op', () async {
        await service.init();
        await service.init();

        // Each config call should still only have happened once.
        verify(() => player.setAudioContext(any())).called(1);
        verify(() => tts.setLanguage(any())).called(1);
      });
    });

    // ── handleEvent() before init ─────────────────────────────────────────────

    group('handleEvent() before init()', () {
      test('silently ignores CountdownBeepEvent', () {
        service.handleEvent(
          const CountdownBeepEvent(count: 3, nextIsWork: true),
        );
        verifyNever(() => player.play(any()));
        verifyNever(() => tts.speak(any()));
      });

      test('silently ignores HalfwayBeepEvent', () {
        service.handleEvent(const HalfwayBeepEvent());
        verifyNever(() => player.play(any()));
      });

      test('silently ignores TransitionAnnouncementEvent', () {
        service.handleEvent(
          const TransitionAnnouncementEvent(isWork: true),
        );
        verifyNever(() => player.play(any()));
        verifyNever(() => tts.speak(any()));
      });

      test('silently ignores WorkoutCompleteEvent', () {
        service.handleEvent(const WorkoutCompleteEvent());
        verifyNever(() => player.play(any()));
        verifyNever(() => tts.speak(any()));
      });
    });

    // ── handleEvent() after init ──────────────────────────────────────────────

    group('handleEvent() after init()', () {
      setUp(() async => service.init());

      test('CountdownBeepEvent plays a tone without TTS', () {
        service.handleEvent(
          const CountdownBeepEvent(count: 2, nextIsWork: false),
        );

        verify(() => player.play(any())).called(1);
        verifyNever(() => tts.speak(any()));
      });

      test('HalfwayBeepEvent plays a tone without TTS', () {
        service.handleEvent(const HalfwayBeepEvent());

        verify(() => player.play(any())).called(1);
        verifyNever(() => tts.speak(any()));
      });

      group('TransitionAnnouncementEvent', () {
        test('work segment plays go tone then speaks "Go" after delay', () {
          fakeAsync((fake) {
            service.handleEvent(
              const TransitionAnnouncementEvent(isWork: true, isNewRound: false),
            );

            verify(() => player.play(any())).called(1);
            verifyNever(() => tts.speak(any()));

            fake.elapse(const Duration(milliseconds: 200));

            verify(() => tts.speak('Go')).called(1);
          });
        });

        test('new-round transition speaks "Next round" instead of "Go"', () {
          fakeAsync((fake) {
            service.handleEvent(
              const TransitionAnnouncementEvent(isWork: true, isNewRound: true),
            );

            fake.elapse(const Duration(milliseconds: 200));

            verify(() => tts.speak('Next round')).called(1);
            verifyNever(() => tts.speak('Go'));
          });
        });

        test('rest segment plays rest tone then speaks "Rest" after delay', () {
          fakeAsync((fake) {
            service.handleEvent(
              const TransitionAnnouncementEvent(isWork: false),
            );

            verify(() => player.play(any())).called(1);
            verifyNever(() => tts.speak(any()));

            fake.elapse(const Duration(milliseconds: 250));

            verify(() => tts.speak('Rest')).called(1);
          });
        });
      });

      test('WorkoutCompleteEvent plays tone then speaks after 1 s delay', () {
        fakeAsync((fake) {
          service.handleEvent(const WorkoutCompleteEvent());

          verify(() => player.play(any())).called(1);
          verifyNever(() => tts.speak(any()));

          fake.elapse(const Duration(milliseconds: 1100));

          verify(() => tts.speak('Workout complete')).called(1);
        });
      });
    });

    // ── dispose() ─────────────────────────────────────────────────────────────

    test('dispose() releases the player and stops TTS', () async {
      await service.dispose();

      verify(() => player.dispose()).called(1);
      verify(() => tts.stop()).called(1);
    });
  });
}
