import '../../domain/entities/destination_entity.dart';

class DestinationModel extends DestinationEntity {
  const DestinationModel({
    required super.destinationId,
    required super.name,
    required super.x,
    required super.y,
    super.floor,
    super.address,
    super.doorLocation,
  });

  factory DestinationModel.fromJson(Map<String, dynamic> json) {
    // Support both x/y and latitude/longitude field names
    final xValue = json['x'] ?? json['latitude'] ?? 0;
    final yValue = json['y'] ?? json['longitude'] ?? 0;
    final doorLocationJson = json['door_location'] as Map<String, dynamic>?;

    return DestinationModel(
      destinationId: json['id'] as String,
      name: json['name'] as String,
      x: (xValue as num).toDouble(),
      y: (yValue as num).toDouble(),
      floor: json['floor'] as String?,
      address: json['address'] as String?,
      doorLocation: doorLocationJson == null
          ? null
          : DoorLocationEntity(
              x: (doorLocationJson['x'] as num).toDouble(),
              y: (doorLocationJson['y'] as num).toDouble(),
            ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': destinationId,
      'name': name,
      'x': x,
      'y': y,
      'floor': floor,
      'address': address,
      if (doorLocation != null)
        'door_location': {
          'x': doorLocation!.x,
          'y': doorLocation!.y,
        },
    };
  }

  factory DestinationModel.fromEntity(DestinationEntity entity) {
    return DestinationModel(
      destinationId: entity.destinationId,
      name: entity.name,
      x: entity.x,
      y: entity.y,
      floor: entity.floor,
      address: entity.address,
      doorLocation: entity.doorLocation,
    );
  }

  static List<DestinationModel> fromJsonList(Map<String, dynamic> json) {
    final destinations = json['destinations'] as List<dynamic>;
    return destinations
        .map((e) => DestinationModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
