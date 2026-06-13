import 'package:equatable/equatable.dart';
import '../../../destination/domain/entities/destination_entity.dart';

abstract class NavigationEvent extends Equatable {
  const NavigationEvent();

  @override
  List<Object?> get props => [];
}

/// Re-emits the current NavigationReady state with a fresh headingAtStart.
/// Used when navigating from the overview page so the heading is captured
/// at "Start Navigation" tap time, not during overview initialization.
class RefreshHeadingAtStartEvent extends NavigationEvent {
  final double heading;
  const RefreshHeadingAtStartEvent(this.heading);

  @override
  List<Object?> get props => [heading];
}

class InitializeNavigationEvent extends NavigationEvent {
  final DestinationEntity destination;
  final String? imagePath;
  final Map<String, dynamic>? userPickedCoordinates;
  final String? pickedFloor;
  final double? heading;

  const InitializeNavigationEvent(
    this.destination, {
    this.imagePath,
    this.userPickedCoordinates,
    this.pickedFloor,
    this.heading,
  });

  @override
  List<Object?> get props => [
    destination,
    imagePath,
    userPickedCoordinates,
    pickedFloor,
    heading,
  ];
}

class ToggleShowDoorsNavigationEvent extends NavigationEvent {
  const ToggleShowDoorsNavigationEvent();
}
