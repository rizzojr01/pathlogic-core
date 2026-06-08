import 'package:equatable/equatable.dart';

/// One snapshot of the dominant wall direction extracted by the native ARKit
/// scene reconstruction layer (LiDAR-only). The yaw is folded onto a half
/// circle [0, 180) because walls have no front/back orientation.
class WallObservation extends Equatable {
  /// Yaw of the dominant wall normal, in degrees, in the ARKit world frame
  /// (East = +X, +Z = South). Range: [0, 180).
  final double dominantWallYawDeg;

  /// Fraction of weighted face area concentrated in the peak yaw bin.
  /// Range: [0, 1]. Higher = sharper corridor.
  final double confidence;

  /// Number of mesh faces classified as `wall` that contributed to this
  /// observation.
  final int sampleCount;

  final DateTime timestamp;

  const WallObservation({
    required this.dominantWallYawDeg,
    required this.confidence,
    required this.sampleCount,
    required this.timestamp,
  });

  @override
  List<Object?> get props => [
        dominantWallYawDeg,
        confidence,
        sampleCount,
        timestamp,
      ];
}
