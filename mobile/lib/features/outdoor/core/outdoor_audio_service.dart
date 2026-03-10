import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'outdoor_workout_engine.dart';

/// Converts [OutdoorAnnouncement]s emitted by [OutdoorWorkoutEngine] into
/// spoken TTS output.
///
/// Designed for outdoor running:
///   • TTS-only — clear voice over music or ambient sound.
///   • Configured for background/lock-screen playback on both platforms.
///   • Injectable [FlutterTts] for unit testing without real TTS.
///
/// Usage:
/// ```dart
/// final audio = ref.read(outdoorAudioServiceProvider);
/// await audio.init();
/// engine.announcementStream.listen(audio.handleAnnouncement);
/// ```
class OutdoorAudioService {
  OutdoorAudioService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _initialized = false;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  /// Configures the TTS engine for outdoor playback.
  ///
  /// Must be called once before [handleAnnouncement].
  /// Idempotent — safe to call multiple times.
  Future<void> init() async {
    if (_initialized) return;

    // iOS: share the AVAudioSession so TTS plays when the screen is locked
    // and routes correctly to Bluetooth headphones.
    if (Platform.isIOS) {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        ],
        IosTextToSpeechAudioMode.defaultMode,
      );
    }

    // Cross-platform: clear, slightly slower than default, neutral pitch,
    // full volume so it cuts through wind noise.
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _initialized = true;
  }

  /// Speaks the announcement appropriate for [announcement].
  ///
  /// Silently ignored if [init] has not yet been called.
  Future<void> handleAnnouncement(OutdoorAnnouncement announcement) async {
    if (!_initialized) return;

    final text = switch (announcement) {
      SegmentStartAnnouncement(:final text) => text,
      CountdownAnnouncement(:final value) => '$value',
      DistanceAnnouncement(:final text) => text,
      HalfwayAnnouncement() => 'Halfway',
      TimeRemainingAnnouncement(:final text) => text,
      PaceAnnouncement(:final text) => text,
    };

    await _tts.speak(text);
  }

  Future<void> dispose() async {
    await _tts.stop();
    _initialized = false;
  }
}

/// Riverpod provider. Initialised lazily by the first screen that calls
/// [OutdoorAudioService.init].
final outdoorAudioServiceProvider = Provider<OutdoorAudioService>((ref) {
  final service = OutdoorAudioService();
  ref.onDispose(service.dispose);
  return service;
});
