import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/image_utils.dart';
import '../../../../core/utils/logger.dart';
import '../../../../injection.dart';
import '../../../../shared/services/destinations_cache_service.dart';
import '../../../../shared/services/device_id_service.dart';
import '../../../../shared/services/floor_plan_cache_service.dart';
import '../../../../shared/services/location_config_service.dart';
import '../../../ar_navigation/domain/entities/ar_pose_entity.dart';
import '../../../ar_navigation/domain/repositories/ar_tracking_repository.dart';
import '../../../ar_navigation/domain/repositories/spatial_audio_repository.dart';
import '../../../ar_navigation/domain/services/ar_transformation_service.dart';
import '../../../destination/domain/entities/destination_entity.dart';
import '../../../localization_history/domain/entities/localization_history_entity.dart';
import '../../../localization_history/domain/usecases/save_localization_history_usecase.dart';
import '../../../locate_me/domain/entities/user_position_entity.dart';
import '../../../locate_me/domain/usecases/get_destinations_usecase.dart';
import '../../domain/entities/location_entity.dart';
import '../../domain/usecases/get_route_usecase.dart';
import 'navigation_event.dart';
import 'navigation_state.dart';

class NavigationBloc extends Bloc<NavigationEvent, NavigationState> {
  final GetRouteUseCase getRouteUseCase;
  final GetDestinationsUseCase getDestinationsUseCase;
  final LocationConfigService locationConfigService;
  final FloorPlanCacheService floorPlanCacheService;
  final DestinationsCacheService destinationsCacheService;
  final SaveLocalizationHistoryUseCase saveLocalizationHistoryUseCase;
  final DeviceIdService deviceIdService;

  // AR Dependencies
  final ArTrackingRepository arTrackingRepository;
  final SpatialAudioRepository spatialAudioRepository;
  final ArTransformationService arTransformationService;

  StreamSubscription<ArPoseEntity>? _arPoseSubscription;
  ArPoseEntity? _originArPose;
  UserPositionEntity? _referenceMapPose;
  double _metersPerPixel = 1.0;

  NavigationBloc({
    required this.getRouteUseCase,
    required this.getDestinationsUseCase,
    required this.locationConfigService,
    required this.floorPlanCacheService,
    required this.destinationsCacheService,
    required this.saveLocalizationHistoryUseCase,
    required this.deviceIdService,
    required this.arTrackingRepository,
    required this.spatialAudioRepository,
    required this.arTransformationService,
  }) : super(const NavigationInitial()) {
    on<InitializeNavigationEvent>(_onInitializeNavigation);
    on<ArPoseUpdatedEvent>(_onArPoseUpdated);
    on<ToggleArViewEvent>(_onToggleArView);
  }

  @override
  Future<void> close() {
    _arPoseSubscription?.cancel();
    arTrackingRepository.stopSession();
    spatialAudioRepository.stopDirectionalGuidance();
    return super.close();
  }

  Future<void> _onInitializeNavigation(
    InitializeNavigationEvent event,
    Emitter<NavigationState> emit,
  ) async {
    final place = locationConfigService.place;
    final building = locationConfigService.building;
    final floor = event.pickedFloor ?? locationConfigService.floor;
    final destinationId = event.destination.destinationId;
    final sessionId = deviceIdService.getDeviceId();
    final useSampleImage = locationConfigService.useSampleImage;

    emit(const NavigationLoading(message: 'Preparing your route...'));

    final floorPlanBase64 = await floorPlanCacheService.getCachedFloorPlanBase64(
      place: place,
      building: building,
      floor: floor,
    );

    if (floorPlanBase64 == null || floorPlanBase64.isEmpty) {
      emit(
        const NavigationError(
          'Floor map not available. Please go to Settings and re-select your '
          'building to download the latest maps.',
        ),
      );
      return;
    }

    final useAlternate = locationConfigService.useAlternateSampleImage;
    bool effectiveUseSample = useSampleImage;
    String base64Image = '';

    if (useAlternate) {
      try {
        final byteData = await rootBundle.load(
          locationConfigService.alternateSampleImagePath,
        );
        base64Image = base64Encode(byteData.buffer.asUint8List());
        effectiveUseSample = false;
      } catch (e) {
        getIt<AppLogger>().error(
          'NavigationBloc: Alternate image loading failed: $e',
        );
      }
    } else if (event.imagePath != null &&
        event.imagePath!.isNotEmpty &&
        !useSampleImage) {
      try {
        if (locationConfigService.enableCompression) {
          base64Image = await ImageUtils.compressAndEncodeImage(
            event.imagePath!,
            maxWidth: locationConfigService.maxWidth,
            maxHeight: locationConfigService.maxHeight,
            quality: locationConfigService.imageQuality,
          );
        } else {
          final imageFile = File(event.imagePath!);
          if (await imageFile.exists()) {
            base64Image = base64Encode(await imageFile.readAsBytes());
          }
        }
      } catch (e) {
        getIt<AppLogger>().error('NavigationBloc: Image processing failed: $e');
      }
    }

    emit(const NavigationLoading(message: 'Calculating route...'));

    final routeResult = await getRouteUseCase(
      GetRouteParams(
        destinationId: destinationId,
        place: place,
        building: building,
        floor: floor,
        sessionId: sessionId,
        useSampleImage: effectiveUseSample,
        base64Image: base64Image,
        saveFrame: locationConfigService.saveFrame,
        multiFloorNavigation: locationConfigService.multiFloorNavigation,
        imageCompression: {
          'enable_compression': locationConfigService.enableCompression,
          'max_height': locationConfigService.maxHeight,
          'max_width': locationConfigService.maxWidth,
          'quality': locationConfigService.imageQuality,
        },
        userPickedCoordinates: event.userPickedCoordinates,
        heading: event.heading,
        offsetInMeters: locationConfigService.offsetInMeters,
      ),
    );

    await routeResult.fold(
      (failure) async => emit(NavigationError(failure.message)),
      (route) async {
        final actualStartingFloor = route.multiFloorSteps.isNotEmpty
            ? route.multiFloorSteps.first.floor
            : floor;

        // ── Step 4: Load destinations from cache for all route floors ─────────
        List<DestinationEntity> destinations = [];
        final Map<String, List<DestinationEntity>> destinationsByFloor = {};

        String normaliseFloor(String f) =>
            f.replaceAll('_floor', '').replaceAll('_', '').trim().toLowerCase();

        Future<List<DestinationEntity>> fetchDestsForFloor(
          String floorKey,
        ) async {
          final cached = destinationsCacheService.getCachedDestinations(
            place: place,
            building: building,
            floor: floorKey,
            multiFloor: locationConfigService.multiFloorNavigation,
          );
          if (cached != null && cached.isNotEmpty) return cached;

          final result = await getDestinationsUseCase(
            GetDestinationsParams(
              building: building,
              floor: floorKey,
              place: place,
              includeCoordinates: true,
              unavMultifloor: locationConfigService.multiFloorNavigation,
            ),
          );
          final allDests = result.getOrElse(() => []);
          if (allDests.isEmpty) return [];

          final Map<String, List<DestinationEntity>> grouped = {};
          for (final d in allDests) {
            final normDest = d.floor != null
                ? normaliseFloor(d.floor!)
                : normaliseFloor(floorKey);
            grouped.putIfAbsent(normDest, () => []).add(d);
          }

          for (final entry in grouped.entries) {
            final rawKey = route.multiFloorSteps
                .map((s) => s.floor)
                .firstWhere(
                  (f) => normaliseFloor(f) == entry.key,
                  orElse: () => floorKey,
                );
            await destinationsCacheService.cacheDestinations(
              place: place,
              building: building,
              floor: rawKey,
              multiFloor: locationConfigService.multiFloorNavigation,
              destinations: entry.value,
            );
          }

          return grouped[normaliseFloor(floorKey)] ?? [];
        }

        await Future.wait(
          route.multiFloorSteps.map((step) async {
            final floorKey = step.floor;
            final dests = await fetchDestsForFloor(floorKey);
            if (dests.isNotEmpty) {
              destinationsByFloor[floorKey] = dests;
              if (floorKey == actualStartingFloor) {
                destinations = dests;
              }
            }
          }),
        );

        final Map<String, String> floorPlansByFloor = {};
        for (final step in route.multiFloorSteps) {
          final cached = await floorPlanCacheService.getCachedFloorPlanBase64(
            place: place,
            building: building,
            floor: step.floor,
          );
          if (cached != null && cached.isNotEmpty) {
            floorPlansByFloor[step.floor] = cached;
          }
        }

        await saveLocalizationHistoryUseCase(
          LocalizationHistoryEntity(
            historyId: DateTime.now().millisecondsSinceEpoch,
            userIdentifier: deviceIdService.getDeviceId(),
            identifierType: 'device',
            sessionId: sessionId,
            destinationId: destinationId,
            destinationName: event.destination.name,
            building: building,
            floor: actualStartingFloor,
            place: place,
            createdAt: DateTime.now(),
          ),
        );

        // ── AR Initialization ───────────────────────────────────────────────
        // Calculate scale (meters per pixel) from the first route step
        if (route.steps.isNotEmpty) {
          final firstStep = route.steps.first;
          final dx = firstStep.to.x - firstStep.from.x;
          final dy = firstStep.to.y - firstStep.from.y;
          final pixelDist = math.sqrt(dx * dx + dy * dy);
          if (pixelDist > 0 && firstStep.distanceMeters > 0) {
            _metersPerPixel = firstStep.distanceMeters / pixelDist;
            getIt<AppLogger>().info(
              'NavigationBloc: Calculated scale: ${_metersPerPixel.toStringAsFixed(4)} m/px',
            );
          }
        }

        _referenceMapPose = UserPositionEntity(
          x: route.origin.x,
          y: route.origin.y,
          angle: event.heading ?? 0.0,
          floor: actualStartingFloor,
        );
        _originArPose = null;

        await arTrackingRepository.startSession();
        await spatialAudioRepository.init();

        _arPoseSubscription?.cancel();
        _arPoseSubscription = arTrackingRepository.watchPose().listen((pose) {
          add(ArPoseUpdatedEvent(pose));
        });

        emit(
          NavigationReady(
            currentLocation: route.origin.copyWith(floor: actualStartingFloor),
            route: route,
            floorPlanBase64:
                floorPlansByFloor[actualStartingFloor] ?? floorPlanBase64,
            destinations: destinations,
            floorPlansByFloor: floorPlansByFloor,
            destinationsByFloor: destinationsByFloor,
            heading: event.heading,
          ),
        );
      },
    );
  }

  void _onArPoseUpdated(
    ArPoseUpdatedEvent event,
    Emitter<NavigationState> emit,
  ) {
    if (state is! NavigationReady) return;
    final currentState = state as NavigationReady;

    final arPose = event.pose;
    
    // ── Origin Alignment ───────────────────────────────────────────────────
    // We wait for a high-confidence pose before locking in the origin.
    // This ensures the AR coordinate system is stable.
    if (_originArPose == null) {
      if (arPose.confidence >= 0.8) {
        _originArPose = arPose;
        getIt<AppLogger>().info(
          'NavigationBloc: AR Origin locked at confidence ${arPose.confidence}',
        );
      } else {
        // Still waiting for stable tracking...
        return;
      }
    }

    if (_referenceMapPose != null && _originArPose != null) {
      // 1. Transform AR pose to map position
      final updatedUserPosition = arTransformationService.transformArToMap(
        currentArPose: arPose,
        originArPose: _originArPose!,
        referenceMapPose: _referenceMapPose!,
        metersPerPixel: _metersPerPixel,
      );

      // 2. Update 3D Overlay
      _update3dOverlay(currentState, arPose);

      // 3. Update Spatial Audio
      _updateSpatialAudio(updatedUserPosition, currentState);

      // 4. Emit updated state
      emit(
        currentState.copyWith(
          currentLocation: currentState.currentLocation.copyWith(
            x: updatedUserPosition.x,
            y: updatedUserPosition.y,
            ang: updatedUserPosition.angle,
          ),
          heading: updatedUserPosition.angle,
          currentArPose: arPose,
        ),
      );
    }
  }

  void _onToggleArView(
    ToggleArViewEvent event,
    Emitter<NavigationState> emit,
  ) {
    if (state is! NavigationReady) return;
    final currentState = state as NavigationReady;
    emit(currentState.copyWith(isArViewEnabled: event.showAr));
  }

  void _update3dOverlay(NavigationReady state, ArPoseEntity currentArPose) {
    if (_originArPose == null || _referenceMapPose == null) return;

    final routePoints = state.route.steps.map((s) => s.to).toList();

    final arPathPoints = routePoints.map((p) {
      final worldPoint = arTransformationService.transformMapToArWorld(
        targetX: p.x,
        targetY: p.y,
        originArPose: _originArPose!,
        referenceMapPose: _referenceMapPose!,
        metersPerPixel: _metersPerPixel,
      );
      return ArPoseEntity(
        x: worldPoint.x,
        y: currentArPose.y, // Keep at same vertical level
        z: -worldPoint.y, // Point.y is Z in AR
        heading: 0,
        confidence: 1.0,
        timestamp: DateTime.now(),
      );
    }).toList();

    arTrackingRepository.updateOverlay(
      activePath: arPathPoints,
      nextWaypoint: arPathPoints.isNotEmpty ? arPathPoints.first : null,
      destination: arPathPoints.isNotEmpty ? arPathPoints.last : null,
    );
  }

  void _updateSpatialAudio(
    UserPositionEntity userPos,
    NavigationReady state,
  ) {
    if (state.route.steps.isEmpty) return;

    final nextStep = state.route.steps.first;
    final dx = nextStep.to.x - userPos.x;
    final dy = nextStep.to.y - userPos.y;
    final distancePx = math.sqrt(dx * dx + dy * dy);
    final distanceMeters = distancePx * _metersPerPixel;

    final targetAngle = math.atan2(dy, dx) * 180 / math.pi;
    final relativeAngle = (targetAngle - userPos.angle + 540) % 360 - 180;

    spatialAudioRepository.updateDirectionalGuidance(
      isActive: true,
      relativeAngleDeg: relativeAngle,
      distanceMeters: distanceMeters,
    );
  }
}
