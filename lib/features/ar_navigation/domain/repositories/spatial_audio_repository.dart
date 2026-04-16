enum SpatialAudioCueType {
  waypointAdvanced,
  waypointRegressed,
  approachingWaypoint,
  turnNow,
  offRoute,
  arrived,
}

abstract class SpatialAudioRepository {
  /// Initializes the spatial audio engine.
  Future<void> init();

  /// Disposes of the spatial audio engine.
  Future<void> dispose();

  /// Plays a short directional cue (e.g., chime).
  Future<void> playCue(SpatialAudioCueType type);

  /// Updates the continuous directional guidance (beacons).
  Future<void> updateDirectionalGuidance({
    required bool isActive,
    required double relativeAngleDeg,
    required double distanceMeters,
    double severity = 1.0,
  });

  /// Stops all directional guidance.
  Future<void> stopDirectionalGuidance();
}
