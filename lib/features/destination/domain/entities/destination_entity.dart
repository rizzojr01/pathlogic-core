import '../../../../core/base/base_entity.dart';

class DoorLocationEntity extends BaseEntity {
  final double x;
  final double y;

  const DoorLocationEntity({required this.x, required this.y});

  @override
  String? get id => null;

  @override
  List<Object?> get props => [x, y];
}

class DestinationEntity extends BaseEntity {
  final String destinationId;
  final String name;
  final double x;
  final double y;
  final String? floor;
  final String? address;
  final DoorLocationEntity? doorLocation;

  const DestinationEntity({
    required this.destinationId,
    required this.name,
    required this.x,
    required this.y,
    this.floor,
    this.address,
    this.doorLocation,
  });

  @override
  String? get id => destinationId;

  @override
  List<Object?> get props => [
    destinationId,
    name,
    x,
    y,
    floor,
    address,
    doorLocation,
  ];
}
