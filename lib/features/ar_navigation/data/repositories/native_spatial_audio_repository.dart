import 'package:flutter/services.dart';
import '../../domain/repositories/spatial_audio_repository.dart';

class NativeSpatialAudioRepository implements SpatialAudioRepository {
  static const _methodChannel = MethodChannel('unav/audio/spatial_method');

  @override
  Future<void> init() async {
    // Initialized on native side usually
  }

  @override
  Future<void> dispose() async {
    await _methodChannel.invokeMethod('stopOffRouteAlert');
  }

  @override
  Future<void> playCue(SpatialAudioCueType type) async {
    await _methodChannel.invokeMethod('playCue', {
      'cueType': type.name,
    });
  }

  @override
  Future<void> updateDirectionalGuidance({
    required bool isActive,
    required double relativeAngleDeg,
    required double distanceMeters,
    double severity = 1.0,
  }) async {
    if (!isActive) {
      await stopDirectionalGuidance();
      return;
    }
    await _methodChannel.invokeMethod('updateOffRouteAlert', {
      'relativeAngleDeg': relativeAngleDeg,
      'sourceDistanceMeters': distanceMeters,
      'severity': severity,
    });
  }

  @override
  Future<void> stopDirectionalGuidance() async {
    await _methodChannel.invokeMethod('stopOffRouteAlert');
  }
}
