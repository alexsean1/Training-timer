import 'dart:math';
import 'dart:typed_data';

/// Generates raw PCM-16 WAV byte data for simple audio tones.
///
/// All output is mono, 22 050 Hz, 16-bit signed PCM wrapped in a standard
/// RIFF/WAVE header so it can be played directly via [audioplayers]
/// `BytesSource`.
abstract final class ToneGenerator {
  static const int _sampleRate = 22050;

  // ─── Pre-generated buffers (computed once, reused every tick) ──────────────

  /// Short neutral beep for countdown (3-2-1).  880 Hz, 180 ms.
  static final Uint8List countdownBeep =
      _sineTone(frequencyHz: 880.0, durationMs: 180, amplitude: 0.65);

  /// Higher-pitch "Go!" tone.  1047 Hz (C6), 260 ms.
  static final Uint8List goTone =
      _sineTone(frequencyHz: 1046.5, durationMs: 260, amplitude: 0.60);

  /// Lower-pitch "Rest!" tone.  523 Hz (C5), 320 ms.
  static final Uint8List restTone =
      _sineTone(frequencyHz: 523.25, durationMs: 320, amplitude: 0.60);

  /// Single quiet tick for the halfway marker.  660 Hz, 140 ms.
  static final Uint8List halfwayBeep =
      _sineTone(frequencyHz: 660.0, durationMs: 140, amplitude: 0.45);

  /// Three-note ascending fanfare for workout completion.
  static final Uint8List completionTone = _completionFanfare();

  /// Near-silent 1-second tone for iOS background audio keepalive.
  ///
  /// Looped during a workout so the AVAudioSession stays active even during
  /// silent REST segments, preventing iOS from suspending the app.
  /// Amplitude 0.0002 is ~80 dB below full scale — inaudible in any context.
  static final Uint8List keepalive =
      _sineTone(frequencyHz: 440.0, durationMs: 1000, amplitude: 0.0002);

  // ─── Internal helpers ───────────────────────────────────────────────────────

  /// Generates a single sine-wave tone with linear fade-in/out.
  static Uint8List _sineTone({
    required double frequencyHz,
    required int durationMs,
    double amplitude = 0.6,
  }) {
    final numSamples = _sampleRate * durationMs ~/ 1000;
    final fadeSamples = (_sampleRate * 15 ~/ 1000).clamp(1, numSamples ~/ 4);
    final buffer = Int16List(numSamples);

    for (var i = 0; i < numSamples; i++) {
      final t = i / _sampleRate;
      var env = 1.0;
      if (i < fadeSamples) env = i / fadeSamples;
      if (i > numSamples - fadeSamples) {
        env = (numSamples - i) / fadeSamples;
      }
      buffer[i] = (sin(2 * pi * frequencyHz * t) * amplitude * env * 32767)
          .round()
          .clamp(-32768, 32767);
    }
    return _wrapWav(buffer);
  }

  /// C5 → E5 → G5 ascending arpeggio with 80 ms silence gaps.
  static Uint8List _completionFanfare() {
    final c5 = _sineTone(frequencyHz: 523.25, durationMs: 220, amplitude: 0.55);
    final e5 = _sineTone(frequencyHz: 659.25, durationMs: 220, amplitude: 0.55);
    final g5 = _sineTone(frequencyHz: 783.99, durationMs: 420, amplitude: 0.55);
    final gap = _silence(durationMs: 80);
    return _concat([c5, gap, e5, gap, g5]);
  }

  /// Generates a WAV buffer containing pure silence.
  static Uint8List _silence({required int durationMs}) {
    final numSamples = _sampleRate * durationMs ~/ 1000;
    return _wrapWav(Int16List(numSamples));
  }

  /// Concatenates multiple WAV buffers by stripping all headers except the
  /// first, merging the raw PCM data, and re-wrapping in a single WAV header.
  static Uint8List _concat(List<Uint8List> wavs) {
    // Each WAV has a 44-byte header; extract the raw PCM regions.
    final pcmChunks = wavs.map((w) => w.sublist(44)).toList();
    final totalBytes = pcmChunks.fold(0, (s, c) => s + c.length);
    final merged = Uint8List(totalBytes);
    var offset = 0;
    for (final chunk in pcmChunks) {
      merged.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return _wrapWav(Int16List.view(merged.buffer));
  }

  /// Wraps a [Int16List] of PCM samples in a minimal RIFF/WAVE header.
  static Uint8List _wrapWav(Int16List samples) {
    const channels = 1;
    const bitsPerSample = 16;
    final dataSize = samples.length * 2;
    final fileSize = 44 + dataSize;
    final bytes = Uint8List(fileSize);
    final bd = ByteData.view(bytes.buffer);

    // RIFF chunk descriptor
    bytes.setRange(0, 4, [0x52, 0x49, 0x46, 0x46]); // 'RIFF'
    bd.setUint32(4, fileSize - 8, Endian.little);
    bytes.setRange(8, 12, [0x57, 0x41, 0x56, 0x45]); // 'WAVE'

    // fmt sub-chunk
    bytes.setRange(12, 16, [0x66, 0x6D, 0x74, 0x20]); // 'fmt '
    bd.setUint32(16, 16, Endian.little); // sub-chunk size
    bd.setUint16(20, 1, Endian.little); // PCM = 1
    bd.setUint16(22, channels, Endian.little);
    bd.setUint32(24, _sampleRate, Endian.little);
    bd.setUint32(28, _sampleRate * channels * bitsPerSample ~/ 8, Endian.little);
    bd.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
    bd.setUint16(34, bitsPerSample, Endian.little);

    // data sub-chunk
    bytes.setRange(36, 40, [0x64, 0x61, 0x74, 0x61]); // 'data'
    bd.setUint32(40, dataSize, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      bd.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return bytes;
  }
}
