import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';
import '../utils/logger.dart';
import '../../injection.dart';

/// Static phrases → mp3 filename under assets/voice/.
/// Add a new entry here + drop the mp3 in assets/voice/ to enable it.
/// Anything not in this map falls through to flutter_tts.
const Map<String, String> _phraseAudio = {
  'Welcome. Please select your destination.': 'welcome.mp3',
  'Search for your destination.': 'search_destination.mp3',
  'Please capture a photo to find your location.': 'capture_photo.mp3',
  'Tap the capture button at the bottom to find your location.':
      'tap_capture.mp3',
  'Capturing photo...': 'capturing.mp3',
  'Re-localizing...': 'relocalizing.mp3',
  'Location updated.': 'location_updated.mp3',
  'Failed to update location.': 'location_failed.mp3',
  'Navigation started. You can tap the camera view to update your location anytime.':
      'navigation_started.mp3',
  'Destination selected. Proceeding to camera.': 'destination_selected.mp3',
};

class SpeechService {
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  final _logger = getIt<AppLogger>();

  SpeechService() {
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage("en-US");
      // Rate scale differs per platform: iOS/Android use 0.0–1.0 where ~0.5 is
      // natural; web (SpeechSynthesis API) uses 0.1–10.0 where 1.0 is natural.
      await _flutterTts.setSpeechRate(kIsWeb ? 1.0 : 0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      if (kIsWeb) {
        await _pickBestWebVoice();
      }
    } catch (e) {
      _logger.error('SpeechService: Failed to initialize TTS: $e');
    }
  }

  // Browsers' default SpeechSynthesis voice is usually a low-quality local
  // synth. Pick a higher-quality en-US voice when one is available (Google,
  // Microsoft, or vendor-labelled "Natural"/"Enhanced"/"Premium").
  Future<void> _pickBestWebVoice() async {
    try {
      final voices = await _flutterTts.getVoices as List<dynamic>?;
      if (voices == null || voices.isEmpty) return;
      const preferred = ['google', 'microsoft', 'natural', 'enhanced', 'premium'];
      Map? best;
      for (final key in preferred) {
        best = voices.cast<Map?>().firstWhere(
          (v) {
            if (v == null) return false;
            final name = (v['name'] ?? '').toString().toLowerCase();
            final locale = (v['locale'] ?? '').toString().toLowerCase();
            return name.contains(key) && locale.startsWith('en');
          },
          orElse: () => null,
        );
        if (best != null) break;
      }
      if (best != null) {
        await _flutterTts.setVoice({
          'name': best['name'].toString(),
          'locale': best['locale'].toString(),
        });
        _logger.info('SpeechService: web voice → ${best['name']}');
      }
    } catch (e) {
      _logger.error('SpeechService: voice selection failed: $e');
    }
  }

  /// Speak [text]. If [text] matches a pre-recorded phrase, plays the mp3 for
  /// consistent quality across platforms. Otherwise falls back to the platform
  /// TTS engine.
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    final asset = _phraseAudio[text];
    if (asset != null) {
      try {
        await _flutterTts.stop();
        await _player.stop();
        await _player.play(AssetSource('voice/$asset'));
        _logger.info('SpeechService: Playing asset: $asset ($text)');
        return;
      } catch (e) {
        _logger.error(
          'SpeechService: asset playback failed ($asset), falling back to TTS: $e',
        );
      }
    }
    try {
      await _player.stop();
      await _flutterTts.stop();
      await _flutterTts.speak(text);
      _logger.info('SpeechService: Speaking: $text');
    } catch (e) {
      _logger.error('SpeechService: Error speaking text: $e');
    }
  }

  Future<void> stop() async {
    await _player.stop();
    await _flutterTts.stop();
  }
}
