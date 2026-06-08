import 'package:flutter/services.dart';
import '../../domain/entities/wall_observation.dart';
import '../../domain/repositories/wall_observation_repository.dart';
import '../datasources/ar_channel_contract.dart';

class WallObservationRepositoryImpl implements WallObservationRepository {
  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  WallObservationRepositoryImpl({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel = methodChannel ??
            const MethodChannel(ArChannelContract.methodChannel),
        _eventChannel = eventChannel ??
            const EventChannel(ArChannelContract.wallEventChannel);

  @override
  Future<bool> isSupported() async {
    try {
      final raw = await _methodChannel
          .invokeMethod<Map<dynamic, dynamic>>(
              ArChannelContract.getCapabilitiesMethod);
      if (raw == null) return false;
      final data = Map<String, dynamic>.from(raw);
      return data[ArChannelContract.meshSupportedKey] == true;
    } on PlatformException {
      return false;
    }
  }

  @override
  Stream<WallObservation> watch() {
    return _eventChannel.receiveBroadcastStream().map((event) {
      final data = Map<String, dynamic>.from(event as Map);
      return WallObservation(
        dominantWallYawDeg:
            (data[ArChannelContract.wallDominantYawDegKey] as num?)
                    ?.toDouble() ??
                0,
        confidence:
            (data[ArChannelContract.wallConfidenceKey] as num?)?.toDouble() ??
                0,
        sampleCount:
            (data[ArChannelContract.wallSampleCountKey] as num?)?.toInt() ?? 0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (data[ArChannelContract.timestampKey] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ),
      );
    });
  }
}
