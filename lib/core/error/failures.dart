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

    // 1. Array index / out of bounds errors
    if (lower.contains('rangeerror') || 
        lower.contains('invalid value') || 
        lower.contains('out of range') || 
        lower.contains('index out of bounds') ||
        lower.contains('indexofbounds') ||
        lower.contains('not in range')) {
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

    // 5. Network / Server connection errors
    if (lower.contains('socketexception') || 
        lower.contains('connection refused') || 
        lower.contains('network') ||
        lower.contains('connection timeout') ||
        lower.contains('timed out') ||
        lower.contains('dioexception') ||
        lower.contains('host lookup') ||
        lower.contains('500') ||
        lower.contains('502') ||
        lower.contains('503') ||
        lower.contains('504')) {
      return 'Connection to the server failed. Please check your internet connection and try again.';
    }

    // 6. Authentication / Unauthorized
    if (lower.contains('401') || 
        lower.contains('403') || 
        lower.contains('unauthorized') ||
        lower.contains('forbidden')) {
      return 'Your session has expired or you do not have permission. Please log out and sign back in.';
    }

    // 7. Not found
    if (lower.contains('404') || lower.contains('not found')) {
      return 'The requested resource or location could not be found. Please check your settings or try again.';
    }

    // 8. Camera errors
    if (lower.contains('cameraexception') || 
        lower.contains('camera') ||
        lower.contains('initialize') ||
        lower.contains('failed to capture')) {
      return 'Camera access failed. Please ensure the app has camera permissions and no other app is using the camera, then retry.';
    }

    // 9. Location errors
    if (lower.contains('location') || 
        lower.contains('gps') ||
        lower.contains('geolocator') ||
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
