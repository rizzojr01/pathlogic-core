import 'dart:math' as math;
import 'package:smart_sense/core/utils/logger.dart';
import 'package:smart_sense/injection.dart';
import 'package:smart_sense/features/locate_me/domain/entities/user_position_entity.dart';
import 'package:smart_sense/features/ar_navigation/domain/entities/ar_pose_entity.dart';

class ArTransformationService {
  /// Transforms a raw AR pose into map coordinates (pixels).
  UserPositionEntity transformArToMap({
    required ArPoseEntity currentArPose,
    required ArPoseEntity originArPose,
    required UserPositionEntity referenceMapPose,
    required double metersPerPixel,
  }) {
    // 1. Calculate delta in AR world space (meters)
    final arDeltaX = currentArPose.x - originArPose.x;
    final arDeltaZ = currentArPose.z - originArPose.z;
    
    // ground plane: forward = -Z, right = X
    final dxAr = arDeltaX;
    final dyAr = -arDeltaZ;

    // 2. Calculate rotation alignment
    final alignmentOffset = _normalizeDegrees(referenceMapPose.angle + originArPose.heading);
    final alignmentRad = alignmentOffset * math.pi / 180.0;

    // 3. Rotate AR displacement into Map space using standard 2D rotation
    final rotatedX = (dxAr * math.cos(alignmentRad)) - (dyAr * math.sin(alignmentRad));
    final rotatedY = (dxAr * math.sin(alignmentRad)) + (dyAr * math.cos(alignmentRad));

    // 4. Convert meters to pixels
    final deltaPixelsX = rotatedX / metersPerPixel;
    final deltaPixelsY = rotatedY / metersPerPixel;

    final finalX = referenceMapPose.x + deltaPixelsX;
    final finalY = referenceMapPose.y + deltaPixelsY;
    
    // 5. Calculate final heading
    final finalHeading = _normalizeDegrees(alignmentOffset - currentArPose.heading);

    // Logging to debug disappearing marker
    if (finalX.isNaN || finalY.isNaN || finalX.abs() > 10000 || finalY.abs() > 10000) {
      getIt<AppLogger>().error(
        'ArTransform: EXTREME VALUES DETECTED! '
        'Pos: ($finalX, $finalY), '
        'DeltaAR: ($dxAr, $dyAr), '
        'Scale: $metersPerPixel'
      );
    }

    return UserPositionEntity(
      x: finalX,
      y: finalY,
      angle: finalHeading,
      floor: referenceMapPose.floor,
    );
  }

  math.Point<double> transformMapToArWorld({
    required double targetX,
    required double targetY,
    required ArPoseEntity originArPose,
    required UserPositionEntity referenceMapPose,
    required double metersPerPixel,
  }) {
    final alignmentOffset = _normalizeDegrees(referenceMapPose.angle + originArPose.heading);
    final alignmentRad = alignmentOffset * math.pi / 180.0;

    final dxPixels = targetX - referenceMapPose.x;
    final dyPixels = targetY - referenceMapPose.y;

    final dxMeters = dxPixels * metersPerPixel;
    final dyMeters = dyPixels * metersPerPixel;

    // Rotate back from Map to AR
    final arDeltaX = (dxMeters * math.cos(alignmentRad)) + (dyMeters * math.sin(alignmentRad));
    final arDeltaForward = -(dxMeters * math.sin(alignmentRad)) + (dyMeters * math.cos(alignmentRad));

    return math.Point(
      originArPose.x + arDeltaX,
      -(originArPose.z - arDeltaForward), 
    );
  }

  double _normalizeDegrees(double value) {
    var normalized = value % 360.0;
    if (normalized < 0) normalized += 360.0;
    return normalized;
  }
}
