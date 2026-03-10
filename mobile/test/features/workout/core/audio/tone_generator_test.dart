import 'package:flutter_test/flutter_test.dart';
import 'package:training_timer/features/workout/core/audio/tone_generator.dart';

void main() {
  group('ToneGenerator', () {
    test('countdownBeep is valid WAV (RIFF header + expected size)', () {
      final bytes = ToneGenerator.countdownBeep;
      _expectValidWav(bytes, expectedDurationMs: 180);
    });

    test('goTone is valid WAV', () {
      final bytes = ToneGenerator.goTone;
      _expectValidWav(bytes, expectedDurationMs: 260);
    });

    test('restTone is valid WAV', () {
      final bytes = ToneGenerator.restTone;
      _expectValidWav(bytes, expectedDurationMs: 320);
    });

    test('halfwayBeep is valid WAV', () {
      final bytes = ToneGenerator.halfwayBeep;
      _expectValidWav(bytes, expectedDurationMs: 140);
    });

    test('completionTone is valid WAV and longer than a single beep', () {
      final bytes = ToneGenerator.completionTone;
      // Sanity-check the header
      expect(bytes[0], 0x52); // 'R'
      expect(bytes[1], 0x49); // 'I'
      expect(bytes[2], 0x46); // 'F'
      expect(bytes[3], 0x46); // 'F'
      // Completion tone = C5 + gap + E5 + gap + G5 — must be longer than any
      // single 400 ms beep.
      expect(bytes.length, greaterThan(44 + 22050 * 400 ~/ 1000 * 2));
    });

    test('different tones have different pitches (non-identical PCM data)', () {
      final countdown = ToneGenerator.countdownBeep;
      final go = ToneGenerator.goTone;
      final rest = ToneGenerator.restTone;

      // Skip 44-byte header; compare a sample of PCM bytes.
      final pcmCountdown = countdown.sublist(44, 44 + 100);
      final pcmGo = go.sublist(44, 44 + 100);
      final pcmRest = rest.sublist(44, 44 + 100);

      expect(pcmCountdown, isNot(equals(pcmGo)));
      expect(pcmCountdown, isNot(equals(pcmRest)));
      expect(pcmGo, isNot(equals(pcmRest)));
    });
  });
}

/// Checks that [bytes] starts with a valid RIFF/WAVE header and that the
/// file-size field in the header is consistent with [bytes.length].
void _expectValidWav(List<int> bytes, {required int expectedDurationMs}) {
  // Minimum: 44-byte header + at least 1 sample.
  expect(bytes.length, greaterThan(44));

  // 'RIFF' magic
  expect(bytes[0], 0x52);
  expect(bytes[1], 0x49);
  expect(bytes[2], 0x46);
  expect(bytes[3], 0x46);

  // 'WAVE' marker
  expect(bytes[8], 0x57);
  expect(bytes[9], 0x41);
  expect(bytes[10], 0x56);
  expect(bytes[11], 0x45);

  // 'data' chunk marker
  expect(bytes[36], 0x64);
  expect(bytes[37], 0x61);
  expect(bytes[38], 0x74);
  expect(bytes[39], 0x61);

  // File-size field at offset 4 = bytes.length - 8.
  final reportedSize = bytes[4] |
      (bytes[5] << 8) |
      (bytes[6] << 16) |
      (bytes[7] << 24);
  expect(reportedSize, bytes.length - 8);

  // Duration: at 22 050 Hz mono 16-bit, each sample = 2 bytes.
  // Allow ±1 sample rounding.
  const sampleRate = 22050;
  final expectedSamples = sampleRate * expectedDurationMs ~/ 1000;
  final actualSamples = (bytes.length - 44) ~/ 2;
  expect(
    actualSamples,
    inInclusiveRange(expectedSamples - 1, expectedSamples + 1),
  );
}
