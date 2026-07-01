import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:smart_sense/injection.dart';
import 'package:smart_sense/shared/services/location_config_service.dart';

class ApiRoutes {
  // Base URL
  static String get baseUrl {
    try {
      final useKoyeb = getIt<LocationConfigService>().useKoyebBaseUrl;
      if (useKoyeb) {
        return dotenv.env['KOYEB_BASE_URL'] ?? dotenv.get('BASE_URL');
      }
    } catch (_) {}
    return dotenv.get('BASE_URL');
  }

  // Auth Endpoints
  static const String login = '/auth/login';
  static const String signup = '/auth/signup';
  static const String me = '/auth/me';
  static const String forgotPassword = '/auth/forgot-password';
  static const String resetPassword = '/auth/reset-password';

  // Camera Endpoints
  static const String uploadPhoto = '/photos/upload';

  // Destination Endpoints
  static const String searchDestinations = '/destinations/search';

  // Navigation Endpoints
  static const String getRoute = '/generate-instructions';

  // Locate Me Endpoints
  static const String getFloor = '/get_floor';
  static const String localizeUser = '/localize_user';
  static const String getDestinationsList = '/get_destinations_list';
  static const String getPlaceDetails = '/get_place_details';

  // Map Download Endpoints
  static const String mapDownloadCatalog = '/map_download/catalog';

  // Localization History Endpoints
  static const String localizationHistory = '/localization-history/user';

  // Headers
  static const String authHeader = 'Authorization';
  static const String bearerPrefix = 'Bearer ';
}
