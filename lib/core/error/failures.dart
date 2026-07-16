import 'package:equatable/equatable.dart';
import '../../injection.dart';
import '../utils/logger.dart';

/// Base failure class
abstract class Failure extends Equatable {
  final String message;
  final String rawError;

  Failure(String inputMessage)
      : rawError = inputMessage,
        message = sanitize(inputMessage) {
    _logDeveloperError(inputMessage);
  }

  @override
  List<Object> get props => [message, rawError];

  static String sanitize(String error) {
    final lower = error.toLowerCase();

    // 1. Array index / iterable access / out of bounds errors
    //    Includes StateError from .first/.last/.single/.reduce on an empty
    //    collection, which surfaces as "Bad state: No element".
    if (lower.contains('rangeerror') ||
        lower.contains('invalid value') ||
        lower.contains('out of range') ||
        lower.contains('index out of bounds') ||
        lower.contains('indexofbounds') ||
        lower.contains('not in range') ||
        lower.contains('bad state') ||
        lower.contains('no element') ||
        lower.contains('too few elements') ||
        lower.contains('concurrent modification') ||
        lower.contains('nosuchmethod') ||
        lower.contains('unsupported operation')) {
      return 'An unexpected data processing error occurred. Please restart the current action or go back and try again.';
    }

    // 2. Null check operator / Null pointer errors
    if (lower.contains('null check operator') || 
        lower.contains('was called on null') ||
        lower.contains('null pointer') ||
        lower.contains('is null')) {
      return 'A temporary application state issue occurred. Please reload the current screen or restart the application.';
    }

    // 3. Type cast / Subtype mismatch errors
    if (lower.contains('is not a subtype of') || 
        lower.contains('type mismatch') || 
        lower.contains('cast')) {
      return 'We encountered a data format mismatch. Please verify your inputs or restart the action.';
    }

    // 4. JSON parsing / FormatException
    if (lower.contains('formatexception') || 
        lower.contains('invalid json') ||
        lower.contains('failed to parse')) {
      return 'The system received invalid data from the server. Please check back shortly or retry.';
    }

    // 5. Raw network exceptions that did NOT come through ApiClient (which
    //    already resolves HTTP/status errors to friendly text). Only textual
    //    signatures — no bare status digits, so a backend message that happens
    //    to contain "500" is never clobbered.
    if (lower.contains('socketexception') ||
        lower.contains('connection refused') ||
        lower.contains('failed host lookup') ||
        lower.contains('host lookup') ||
        lower.contains('dioexception')) {
      return 'Connection to the server failed. Please check your internet connection and try again.';
    }

    // 6. Camera errors — match CAMERA-specific signals only. Bare 'camera' or
    // 'initialize' matched generic backend errors (e.g. "failed to initialize
    // localization"), wrongly showing a camera-permission message.
    if (lower.contains('cameraexception') ||
        lower.contains('camera permission') ||
        lower.contains('camera access') ||
        lower.contains('no cameras') ||
        lower.contains('camera is unavailable') ||
        lower.contains('camera in use') ||
        lower.contains('failed to capture')) {
      return 'Camera access failed. Please ensure the app has camera permissions and no other app is using the camera, then retry.';
    }

    // 9. Location / GPS errors — match GPS-specific signals only. Bare
    // 'location' matched localization/backend errors ("localization failed").
    if (lower.contains('gps') ||
        lower.contains('geolocator') ||
        lower.contains('location services') ||
        lower.contains('location permission') ||
        lower.contains('permission denied')) {
      return 'Failed to determine your location. Please ensure location services (GPS) are enabled and permissions are granted.';
    }

    return error;
  }

  static void _logDeveloperError(String raw) {
    try {
      final logger = getIt<AppLogger>();
      logger.error('Developer Detailed Log [Failure]: $raw');
    } catch (_) {
      print('Developer Detailed Log [Failure]: $raw');
    }
  }
}

/// Server failure
class ServerFailure extends Failure {
  ServerFailure(super.message);
}

/// Cache failure
class CacheFailure extends Failure {
  CacheFailure(super.message);
}

/// Network failure
class NetworkFailure extends Failure {
  NetworkFailure(super.message);
}

/// Validation failure
class ValidationFailure extends Failure {
  ValidationFailure(super.message);
}

/// Permission failure
class PermissionFailure extends Failure {
  PermissionFailure(super.message);
}

/// Location failure
class LocationFailure extends Failure {
  LocationFailure(super.message);
}

/// Camera failure
class CameraFailure extends Failure {
  CameraFailure(super.message);
}
