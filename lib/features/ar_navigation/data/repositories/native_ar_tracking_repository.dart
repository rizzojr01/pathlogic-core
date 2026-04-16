import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/entities/ar_pose_entity.dart';
import '../../domain/entities/ar_tracking_state.dart';
import '../../domain/repositories/ar_tracking_repository.dart';

class NativeArTrackingRepository implements ArTrackingRepository {
  static const _methodChannel = MethodChannel('unav/tracking/ar_method');
  static const _eventChannel = EventChannel('unav/tracking/ar_pose_stream');

  @override
  Future<void> startSession() async {
    await _methodChannel.invokeMethod('startSession');
  }

  @override
  Future<void> stopSession() async {
    await _methodChannel.invokeMethod('stopSession');
  }

  @override
  Stream<ArPoseEntity> watchPose() {
    return _eventChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event);
      return ArPoseEntity(
        x: (map['x'] as num).toDouble(),
        y: (map['y'] as num).toDouble(),
        z: (map['z'] as num).toDouble(),
        heading: (map['heading'] as num).toDouble(),
        confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestampMillis'] as int),
      );
    });
  }

  @override
  Stream<ArTrackingState> watchTrackingState() {
    // This could be implemented via another EventChannel if needed
    return const Stream.empty();
  }

  @override
  Future<Uint8List?> captureCurrentFrame() async {
    final result = await _methodChannel.invokeMethod<Uint8List>('captureCurrentFrame');
    return result;
  }

  @override
  Future<void> updateOverlay({
    required List<ArPoseEntity> activePath,
    List<ArPoseEntity>? futurePath,
    ArPoseEntity? nextWaypoint,
    ArPoseEntity? destination,
  }) async {
    await _methodChannel.invokeMethod('updateOverlay', {
      'activePathPoints': activePath.map((e) => _poseToMap(e)).toList(),
      'futurePathPoints': futurePath?.map((e) => _poseToMap(e)).toList(),
      'nextWaypoint': nextWaypoint != null ? _poseToMap(nextWaypoint) : null,
      'destination': destination != null ? _poseToMap(destination) : null,
    });
  }

  @override
  Future<void> clearOverlay() async {
    await _methodChannel.invokeMethod('clearOverlay');
  }

  Map<String, dynamic> _poseToMap(ArPoseEntity pose) {
    return {
      'x': pose.x,
      'y': pose.y,
      'z': pose.z,
    };
  }
}
