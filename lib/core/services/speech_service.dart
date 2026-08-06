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
