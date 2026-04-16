import 'dart:typed_data';
import '../entities/ar_pose_entity.dart';
import '../entities/ar_tracking_state.dart';

abstract class ArTrackingRepository {
  /// Starts the AR session on the device.
  Future<void> startSession();

  /// Stops the AR session.
  Future<void> stopSession();

  /// Stream of pose updates from the AR engine.
  Stream<ArPoseEntity> watchPose();

  /// Stream of tracking state changes.
  Stream<ArTrackingState> watchTrackingState();

  /// Captures the current AR frame as an image (for localization).
  Future<Uint8List?> captureCurrentFrame();

  /// Updates the 3D overlay (path, markers).
  Future<void> updateOverlay({
    required List<ArPoseEntity> activePath,
    List<ArPoseEntity>? futurePath,
    ArPoseEntity? nextWaypoint,
    ArPoseEntity? destination,
  });

  /// Clears all 3D overlays.
  Future<void> clearOverlay();
}
