import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'audio_events.dart';
import 'tone_generator.dart';

/// Handles all audio playback for the workout timer.
///
/// Tones are generated programmatically by [ToneGenerator] and played via
/// [audioplayers].  Spoken announcements ("Go!", "Rest!", etc.) are spoken
/// via [flutter_tts].
///
/// The optional [player] and [tts] constructor parameters exist for
/// dependency injection in tests.  Production code omits them and gets
/// default instances.
///
/// Usage:
/// ```dart
/// final audio = ref.read(workoutAudioServiceProvider);
/// await audio.init();
/// audio.handleEvent(CountdownBeepEvent(count: 3, nextIsWork: true));
/// ```
class WorkoutAudioService {
  WorkoutAudioService({AudioPlayer? player, FlutterTts? tts, AudioPlayer? keepalivePlayer})
      : _player = player ?? AudioPlayer(),
        _tts = tts ?? FlutterTts(),
        _keepalivePlayer = keepalivePlayer ?? AudioPlayer();

  final AudioPlayer _player;
  final FlutterTts _tts;

  /// Dedicated player for the iOS background keepalive tone.
  /// Kept separate so it never interferes with beeps / TTS timing.
  final AudioPlayer _keepalivePlayer;

  bool _initialized = false;

  /// Must be called once before [handleEvent].
  Future<void> init() async {
    if (_initialized) return;

    // Configure the audio session so audio plays over the lock-screen on both
    // platforms and ducks music instead of silencing it.
    await _player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.notification,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        isSpeakerphoneOn: false,
      ),
      iOS: AudioContextIOS(
        // playback → audio continues when the screen is locked
        category: AVAudioSessionCategory.playback,
        options: const {
          // allow music to continue underneath our tones
          AVAudioSessionOptions.mixWithOthers,
          // also duck Siri / other interruptions
          AVAudioSessionOptions.duckOthers,
        },
      ),
    ));

    // TTS settings: clear, slightly slower than default, neutral pitch.
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.1);

    _initialized = true;
  }

  /// Dispatches an [event] to the appropriate playback method.
  void handleEvent(WorkoutAudioEvent event) {
    if (!_initialized) return;
    switch (event) {
      case CountdownBeepEvent():
        _playCountdownBeep();
      case TransitionAnnouncementEvent(:final isWork, :final isNewRound):
        _playTransition(isWork: isWork, isNewRound: isNewRound);
      case HalfwayBeepEvent():
        _playHalfwayBeep();
      case WorkoutCompleteEvent():
        _playWorkoutComplete();
    }
  }

  // ─── Private playback helpers ───────────────────────────────────────────────

  void _playCountdownBeep() {
    _player.play(BytesSource(ToneGenerator.countdownBeep));
  }

  void _playTransition({required bool isWork, bool isNewRound = false}) {
    if (isWork) {
      _player.play(BytesSource(ToneGenerator.goTone));
      // Slight delay lets the tone play before TTS starts.
      Future<void>.delayed(const Duration(milliseconds: 180), () {
        _tts.speak(isNewRound ? 'Next round' : 'Go');
      });
    } else {
      _player.play(BytesSource(ToneGenerator.restTone));
      Future<void>.delayed(const Duration(milliseconds: 220), () {
        _tts.speak('Rest');
      });
    }
  }

  void _playHalfwayBeep() {
    _player.play(BytesSource(ToneGenerator.halfwayBeep));
  }

  void _playWorkoutComplete() {
    _player.play(BytesSource(ToneGenerator.completionTone));
    Future<void>.delayed(const Duration(milliseconds: 1000), () {
      _tts.speak('Workout complete');
    });
  }

  // ─── iOS background keepalive ────────────────────────────────────────────

  /// Starts looping a near-silent tone to keep the iOS AVAudioSession active.
  ///
  /// Without this, iOS suspends the app during silent REST segments, causing
  /// [Timer.periodic] to pause and the timer to fall behind.
  /// Call when a workout starts; pair with [stopKeepalive] on finish/dispose.
  Future<void> startKeepalive() async {
    await _keepalivePlayer.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.notification,
        audioFocus: AndroidAudioFocus.none,
        isSpeakerphoneOn: false,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {AVAudioSessionOptions.mixWithOthers},
      ),
    ));
    await _keepalivePlayer.setReleaseMode(ReleaseMode.loop);
    _keepalivePlayer.play(BytesSource(ToneGenerator.keepalive)).ignore();
  }

  /// Stops the background keepalive tone.
  Future<void> stopKeepalive() async {
    await _keepalivePlayer.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
    await _keepalivePlayer.dispose();
    await _tts.stop();
    _initialized = false;
  }
}

/// Riverpod provider.  Audio service is initialized lazily by the first
/// widget that calls [WorkoutAudioService.init].
final workoutAudioServiceProvider = Provider<WorkoutAudioService>((ref) {
  final service = WorkoutAudioService();
  ref.onDispose(service.dispose);
  return service;
});
