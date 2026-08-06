import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';
import '../utils/logger.dart';
import '../../injection.dart';

class SpeechService {
  final FlutterTts _flutterTts = FlutterTts();
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
    } catch (e) {
      _logger.error('SpeechService: Failed to initialize TTS: $e');
    }
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    try {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
      _logger.info('SpeechService: Speaking: $text');
    } catch (e) {
      _logger.error('SpeechService: Error speaking text: $e');
    }
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }
}
