import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:training_timer/features/outdoor/core/outdoor_audio_service.dart';
import 'package:training_timer/features/outdoor/core/outdoor_workout_engine.dart';

// ─── Mock ─────────────────────────────────────────────────────────────────────

class _MockTts extends Mock implements FlutterTts {}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Stubs every TTS method that [OutdoorAudioService.init] might call.
void _stubTts(_MockTts tts) {
  when(() => tts.setLanguage(any())).thenAnswer((_) async => 1);
  when(() => tts.setSpeechRate(any())).thenAnswer((_) async => 1);
  when(() => tts.setVolume(any())).thenAnswer((_) async => 1);
  when(() => tts.setPitch(any())).thenAnswer((_) async => 1);
  when(() => tts.speak(any())).thenAnswer((_) async => 1);
  when(() => tts.stop()).thenAnswer((_) async => 1);
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late _MockTts tts;
  late OutdoorAudioService service;

  setUp(() {
    tts = _MockTts();
    _stubTts(tts);
    service = OutdoorAudioService(tts: tts);
  });

  tearDown(() async => service.dispose());

  // ── Initialisation ─────────────────────────────────────────────────────────

  group('init', () {
    test('configures language, speech rate, volume, and pitch', () async {
      await service.init();

      verify(() => tts.setLanguage('en-US')).called(1);
      verify(() => tts.setSpeechRate(0.45)).called(1);
      verify(() => tts.setVolume(1.0)).called(1);
      verify(() => tts.setPitch(1.0)).called(1);
    });

    test('is idempotent — TTS configured only once on repeated calls',
        () async {
      await service.init();
      await service.init();
      await service.init();

      verify(() => tts.setLanguage(any())).called(1);
    });
  });

  // ── Pre-init guard ─────────────────────────────────────────────────────────

  group('before init', () {
    test('announcements are silently ignored', () async {
      await service.handleAnnouncement(const SegmentStartAnnouncement('Run!'));
      await service.handleAnnouncement(const CountdownAnnouncement(3));
      await service.handleAnnouncement(const HalfwayAnnouncement());

      verifyNever(() => tts.speak(any()));
    });
  });

  // ── Announcement dispatch ──────────────────────────────────────────────────

  group('after init', () {
    setUp(() async => service.init());

    test('SegmentStartAnnouncement speaks the announcement text', () async {
      await service.handleAnnouncement(const SegmentStartAnnouncement('Run!'));
      verify(() => tts.speak('Run!')).called(1);
    });

    test('SegmentStartAnnouncement speaks rest text', () async {
      await service
          .handleAnnouncement(const SegmentStartAnnouncement('Rest!'));
      verify(() => tts.speak('Rest!')).called(1);
    });

    test('CountdownAnnouncement speaks the number as a string', () async {
      await service.handleAnnouncement(const CountdownAnnouncement(3));
      verify(() => tts.speak('3')).called(1);

      await service.handleAnnouncement(const CountdownAnnouncement(2));
      verify(() => tts.speak('2')).called(1);

      await service.handleAnnouncement(const CountdownAnnouncement(1));
      verify(() => tts.speak('1')).called(1);
    });

    test('DistanceAnnouncement speaks the distance text', () async {
      await service.handleAnnouncement(
          const DistanceAnnouncement('2 kilometres remaining'));
      verify(() => tts.speak('2 kilometres remaining')).called(1);
    });

    test('DistanceAnnouncement speaks metres text', () async {
      await service.handleAnnouncement(
          const DistanceAnnouncement('500 metres remaining'));
      verify(() => tts.speak('500 metres remaining')).called(1);
    });

    test('HalfwayAnnouncement speaks "Halfway"', () async {
      await service.handleAnnouncement(const HalfwayAnnouncement());
      verify(() => tts.speak('Halfway')).called(1);
    });

    test('TimeRemainingAnnouncement speaks the reminder text', () async {
      await service.handleAnnouncement(
          const TimeRemainingAnnouncement('One minute remaining'));
      verify(() => tts.speak('One minute remaining')).called(1);
    });

    test('PaceAnnouncement speaks the pace text', () async {
      const text =
          'Current pace: 5 minutes 30 seconds per kilometre';
      await service.handleAnnouncement(const PaceAnnouncement(text));
      verify(() => tts.speak(text)).called(1);
    });

    test('PaceAnnouncement with whole minutes speaks correctly', () async {
      const text = 'Current pace: 4 minutes per kilometre';
      await service.handleAnnouncement(const PaceAnnouncement(text));
      verify(() => tts.speak(text)).called(1);
    });
  });

  // ── Dispose ────────────────────────────────────────────────────────────────

  group('dispose', () {
    test('stops TTS', () async {
      await service.init();
      await service.dispose();

      verify(() => tts.stop()).called(1);
    });

    test('silences announcements after dispose (resets init flag)', () async {
      await service.init();
      await service.dispose();

      await service.handleAnnouncement(const SegmentStartAnnouncement('Run!'));
      verifyNever(() => tts.speak(any()));
    });
  });
}
