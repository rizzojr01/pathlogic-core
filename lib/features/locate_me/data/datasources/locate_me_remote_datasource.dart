import '../../../../core/base/base_datasource.dart';
import '../../../../core/constants/api_routes.dart';
import '../../../../core/utils/logger.dart';
import '../../../../shared/services/device_id_service.dart';
import '../../../../shared/services/fcm_service.dart';
import '../../../../injection.dart';
import '../../../destination/data/models/destination_model.dart';
import '../../../destination/domain/entities/destination_entity.dart';
import '../models/floor_plan_model.dart';
import '../models/user_position_model.dart';
import '../models/localization_request_model.dart';

class DestinationsListModel {
  final List<DestinationModel> destinations;
  final List<DoorLocationEntity> doors;

  const DestinationsListModel({
    required this.destinations,
    required this.doors,
  });
}

abstract class LocateMeRemoteDataSource {
  /// Get floor plan image from the backend
  Future<FloorPlanModel> getFloorPlan({
    String? building,
    String? floor,
    String? place,
  });

  /// Localize user position based on captured image
  Future<UserPositionModel> localizeUser(LocalizationRequestModel request);

  /// Get list of destinations for the floor
  Future<DestinationsListModel> getDestinationsList({
    required String building,
    required String floor,
    required String place,
    String? deviceId,
    bool includeCoordinates = true,
    bool unavMultifloor = false,
  });
}

class LocateMeRemoteDataSourceImpl extends BaseRemoteDataSource
    implements LocateMeRemoteDataSource {
  LocateMeRemoteDataSourceImpl(super.apiClient);

  @override
  Future<FloorPlanModel> getFloorPlan({
    String? building,
    String? floor,
    String? place,
  }) async {
    return executeCall<FloorPlanModel>(() async {
      final response = await get(
        ApiRoutes.getFloor,
        queryParameters: {
          if (building != null) 'building': building,
          if (floor != null) 'floor': floor,
          if (place != null) 'place': place,
        },
      );
      return FloorPlanModel.fromJson(response);
    }, errorMessage: 'Failed to get floor plan');
  }

  @override
  Future<UserPositionModel> localizeUser(
    LocalizationRequestModel request,
  ) async {
    try {
      final requestData = request.toJson();
      // Add FCM token for backend push notifications
      final fcmToken = getIt<FcmService>().token;
      if (fcmToken != null) {
        requestData['fcm_token'] = fcmToken;
      }

      final response = await post(ApiRoutes.localizeUser, data: requestData);

      final logger = getIt<AppLogger>();
      // Log the orientation returned by the backend
      final orientation =
          response['ang'] ??
          response['result']?['ang'] ??
          response['result']?['result']?['ang'];
      if (orientation != null) {
        logger.info('Backend Orientation (Localization): $orientation°');
      }

      return UserPositionModel.fromJson(response);
    } on LocalizationFailedException catch (e) {
      // Re-throw with the proper error message from the API
      throw Exception(e.message);
    } catch (e) {
      // Handle other exceptions
      if (e is Exception) rethrow;
      throw Exception('Failed to localize user');
    }
  }

  @override
  Future<DestinationsListModel> getDestinationsList({
    required String building,
    required String floor,
    required String place,
    String? deviceId,
    bool includeCoordinates = true,
    bool unavMultifloor = false,
  }) async {
    return executeCall<DestinationsListModel>(() async {
      final fcmToken = getIt<FcmService>().token;
      final response = await post(
        ApiRoutes.getDestinationsList,
        data: {
          'building': building,
          'floor': floor,
          'place': place,
          'device_id': deviceId ?? getIt<DeviceIdService>().getDeviceId(),
          'include_coordinates': includeCoordinates,
          'unav_multifloor': unavMultifloor,
          if (fcmToken != null) 'fcm_token': fcmToken,
        },
      );
      print('DEBUG: getDestinationsList response keys: ${response.keys}');
      if (response['destinations'] != null) {
        final destsList = response['destinations'] as List<dynamic>;
        print('DEBUG: fetched ${destsList.length} destinations');
        if (destsList.isNotEmpty) {
          print('DEBUG: First destination JSON: ${destsList.first}');
        }
      }

      final destsList = (response['destinations'] as List<dynamic>? ?? [])
          .map((e) => DestinationModel.fromJson(e as Map<String, dynamic>))
          .toList();

      final doorsList = (response['door_locations'] as List<dynamic>? ?? [])
          .map((e) => DoorLocationEntity(
                x: ((e as Map<String, dynamic>)['x'] as num).toDouble(),
                y: (e['y'] as num).toDouble(),
              ))
          .toList();

      return DestinationsListModel(destinations: destsList, doors: doorsList);
    }, errorMessage: 'Failed to get destinations list');
  }
}
