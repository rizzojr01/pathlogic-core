import '../../../../core/base/base_state.dart';
import '../../../ar_navigation/domain/entities/ar_pose_entity.dart';
import '../../../destination/domain/entities/destination_entity.dart';
import '../../domain/entities/location_entity.dart';
import '../../domain/entities/route_entity.dart';

abstract class NavigationState extends BaseState {
  const NavigationState();
}

class NavigationInitial extends NavigationState {
  const NavigationInitial();
}

class NavigationLoading extends NavigationState {
  final String? message;

  const NavigationLoading({this.message});

  @override
  List<Object?> get props => [message];
}

class NavigationReady extends NavigationState {
  final LocationEntity currentLocation;
  final RouteEntity route;
  final String? floorPlanBase64;
  final List<DestinationEntity> destinations;

  /// floor key → base64 floor plan (populated for multi-floor routes)
  final Map<String, String> floorPlansByFloor;

  /// floor key → destinations list (populated for multi-floor routes)
  final Map<String, List<DestinationEntity>> destinationsByFloor;

  final double? heading;

  /// AR state
  final bool isArViewEnabled;
  final ArPoseEntity? currentArPose;

  const NavigationReady({
    required this.currentLocation,
    required this.route,
    this.floorPlanBase64,
    this.destinations = const [],
    this.floorPlansByFloor = const {},
    this.destinationsByFloor = const {},
    this.heading,
    this.isArViewEnabled = false,
    this.currentArPose,
  });

  NavigationReady copyWith({
    LocationEntity? currentLocation,
    RouteEntity? route,
    String? floorPlanBase64,
    List<DestinationEntity>? destinations,
    Map<String, String>? floorPlansByFloor,
    Map<String, List<DestinationEntity>>? destinationsByFloor,
    double? heading,
    bool? isArViewEnabled,
    ArPoseEntity? currentArPose,
  }) {
    return NavigationReady(
      currentLocation: currentLocation ?? this.currentLocation,
      route: route ?? this.route,
      floorPlanBase64: floorPlanBase64 ?? this.floorPlanBase64,
      destinations: destinations ?? this.destinations,
      floorPlansByFloor: floorPlansByFloor ?? this.floorPlansByFloor,
      destinationsByFloor: destinationsByFloor ?? this.destinationsByFloor,
      heading: heading ?? this.heading,
      isArViewEnabled: isArViewEnabled ?? this.isArViewEnabled,
      currentArPose: currentArPose ?? this.currentArPose,
    );
  }

  @override
  List<Object?> get props => [
    currentLocation,
    route,
    floorPlanBase64,
    destinations,
    floorPlansByFloor,
    destinationsByFloor,
    heading,
    isArViewEnabled,
    currentArPose,
  ];
}


class NavigationCompleted extends NavigationState {
  const NavigationCompleted();
}

class NavigationError extends NavigationState {
  final String message;

  const NavigationError(this.message);

  @override
  List<Object?> get props => [message];
}
