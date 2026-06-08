import '../entities/wall_observation.dart';

/// Source of throttled wall observations from the native AR layer. Returns
/// an empty stream when the device cannot run LiDAR scene reconstruction.
abstract class WallObservationRepository {
  /// True when the native side reports `meshSupported: true` in its
  /// capabilities response (LiDAR-equipped iPhone/iPad). Returns false on
  /// non-LiDAR devices and on Android.
  Future<bool> isSupported();

  Stream<WallObservation> watch();
}
