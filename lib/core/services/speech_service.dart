import 'package:audioplayers/audioplayers.dart';
import '../utils/logger.dart';
import '../../injection.dart';

/// Static phrases → mp3 filename under assets/voice/.
/// Add a new entry here + drop the mp3 in assets/voice/ to enable it.
/// Anything not in this map is silent — regenerate assets with
/// scripts/gen-voice-assets.sh whenever you add a new phrase.
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
  final AudioPlayer _player = AudioPlayer();
  final _logger = getIt<AppLogger>();

  SpeechService();

  /// Speak [text] by playing its pre-recorded asset. Silent if the phrase
  /// isn't in the map — voice-only phrases live in `_phraseAudio`.
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    final asset = _phraseAudio[text];
    if (asset == null) {
      _logger.warning('SpeechService: no asset for "$text" (silent)');
      return;
    }
    try {
      await _player.stop();
      await _player.play(AssetSource('voice/$asset'));
      _logger.info('SpeechService: Playing asset: $asset ($text)');
    } catch (e) {
      _logger.error('SpeechService: asset playback failed ($asset): $e');
    }
  }

  Future<void> stop() async {
    await _player.stop();
  }
}
