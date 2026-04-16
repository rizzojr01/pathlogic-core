import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/api_routes.dart';
import 'core/network/api_client.dart';
import 'core/services/storage_service.dart';
import 'core/utils/logger.dart';
import 'features/ar_navigation/data/repositories/native_ar_tracking_repository.dart';
import 'features/ar_navigation/data/repositories/native_spatial_audio_repository.dart';
import 'features/ar_navigation/domain/repositories/ar_tracking_repository.dart';
import 'features/ar_navigation/domain/repositories/spatial_audio_repository.dart';
import 'features/ar_navigation/domain/services/ar_transformation_service.dart';
// Auth
import 'features/auth/data/datasources/auth_local_datasource.dart';
import 'features/auth/data/datasources/auth_remote_datasource.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/domain/repositories/auth_repository.dart';
import 'features/auth/domain/usecases/login_usecase.dart';
import 'features/auth/domain/usecases/logout_usecase.dart';
import 'features/auth/domain/usecases/signup_usecase.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
// Camera
import 'features/camera/data/datasources/camera_local_datasource.dart';
import 'features/camera/data/datasources/camera_remote_datasource.dart';
import 'features/camera/data/repositories/camera_repository_impl.dart';
import 'features/camera/domain/repositories/camera_repository.dart';
import 'features/camera/domain/usecases/capture_photo_usecase.dart';
import 'features/camera/domain/usecases/upload_photo_usecase.dart';
import 'features/camera/presentation/bloc/camera_bloc.dart';
// Destination
import 'features/destination/data/datasources/destination_remote_datasource.dart';
import 'features/destination/data/repositories/destination_repository_impl.dart';
import 'features/destination/domain/repositories/destination_repository.dart';
import 'features/destination/domain/usecases/search_destinations_usecase.dart';
import 'features/destination/domain/usecases/select_destination_usecase.dart';
import 'features/destination/presentation/bloc/destination_bloc.dart';
import 'features/destination/presentation/bloc/floor_map_bloc.dart';
import 'features/localization_history/data/datasources/localization_history_local_datasource.dart';
// Localization History
import 'features/localization_history/data/datasources/localization_history_remote_datasource.dart';
import 'features/localization_history/data/repositories/localization_history_repository_impl.dart';
import 'features/localization_history/domain/repositories/localization_history_repository.dart';
import 'features/localization_history/domain/usecases/get_user_localization_history_usecase.dart';
import 'features/localization_history/domain/usecases/save_localization_history_usecase.dart';
import 'features/localization_history/presentation/bloc/localization_history_bloc.dart';
// Locate Me
import 'features/locate_me/data/datasources/locate_me_remote_datasource.dart';
import 'features/locate_me/data/repositories/locate_me_repository_impl.dart';
import 'features/locate_me/domain/repositories/locate_me_repository.dart';
import 'features/locate_me/domain/usecases/get_destinations_usecase.dart';
import 'features/locate_me/domain/usecases/get_floor_plan_usecase.dart';
import 'features/locate_me/domain/usecases/localize_user_usecase.dart';
import 'features/locate_me/presentation/bloc/locate_me_bloc.dart';
// Navigation
import 'features/navigation/data/datasources/navigation_local_datasource.dart';
import 'features/navigation/data/datasources/navigation_remote_datasource.dart';
import 'features/navigation/data/repositories/navigation_repository_impl.dart';
import 'features/navigation/domain/repositories/navigation_repository.dart';
import 'features/navigation/domain/usecases/get_route_usecase.dart';
import 'features/navigation/presentation/bloc/navigation_bloc.dart';
// Profile
import 'features/profile/data/datasources/profile_remote_datasource.dart';
import 'features/profile/data/repositories/profile_repository_impl.dart';
import 'features/profile/domain/repositories/profile_repository.dart';
import 'features/profile/domain/usecases/get_me_usecase.dart';
import 'shared/data/datasources/place_remote_datasource.dart';
import 'shared/presentation/bloc/location_settings_bloc.dart';
import 'shared/services/destinations_cache_service.dart';
import 'shared/services/device_id_service.dart';
import 'shared/services/fcm_service.dart';
import 'shared/services/floor_plan_cache_service.dart';
import 'shared/services/gps_auto_select_service.dart';
// Shared
import 'shared/services/location_config_service.dart';
import 'shared/services/location_service.dart';
import 'shared/services/map_download_service.dart';
import 'shared/services/recent_destinations_service.dart';
import 'shared/services/wifi_auto_select_service.dart';
import 'theme/theme_bloc.dart';

final getIt = GetIt.instance;

Future<void> initializeDependencies() async {
  // External
  final sharedPreferences = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(sharedPreferences);

  // Core
  getIt.registerLazySingleton<AppLogger>(() => AppLogger());
  getIt.registerLazySingleton<StorageService>(() => StorageService(getIt()));
  getIt.registerLazySingleton<ApiClient>(
    () => ApiClient(baseUrl: ApiRoutes.baseUrl, logger: getIt()),
  );

  // Shared Services
  getIt.registerLazySingleton<LocationConfigService>(
    () => LocationConfigService(getIt()),
  );
  final deviceIdService = DeviceIdService(getIt());
  await deviceIdService.init();
  getIt.registerLazySingleton<DeviceIdService>(() => deviceIdService);
  getIt.registerLazySingleton<FloorPlanCacheService>(
    () => FloorPlanCacheService(getIt()),
  );
  getIt.registerLazySingleton<DestinationsCacheService>(
    () => DestinationsCacheService(getIt()),
  );
  getIt.registerLazySingleton<RecentDestinationsService>(
    () => RecentDestinationsService(getIt()),
  );
  getIt.registerLazySingleton<LocationService>(() => LocationService());
  getIt.registerLazySingleton<GpsAutoSelectService>(
    () => GpsAutoSelectService(locationService: getIt(), prefs: getIt()),
  );
  getIt.registerLazySingleton<WifiAutoSelectService>(
    () => WifiAutoSelectService(prefs: getIt()),
  );
  getIt.registerLazySingleton<PlaceRemoteDataSource>(
    () => PlaceRemoteDataSourceImpl(getIt()),
  );
  getIt.registerLazySingleton<MapDownloadService>(
    () => MapDownloadService(getIt()),
  );
  getIt.registerLazySingleton<FcmService>(() => FcmService(logger: getIt()));
  getIt.registerFactory(
    () => LocationSettingsBloc(
      placeRemoteDataSource: getIt(),
      locationConfigService: getIt(),
      floorPlanCacheService: getIt(),
      destinationsCacheService: getIt(),
      gpsAutoSelectService: getIt(),
      wifiAutoSelectService: getIt(),
      locationService: getIt(),
      mapDownloadService: getIt(),
    ),
  );

  // AR Navigation Feature
  getIt.registerLazySingleton<ArTrackingRepository>(
    () => NativeArTrackingRepository(),
  );
  getIt.registerLazySingleton<SpatialAudioRepository>(
    () => NativeSpatialAudioRepository(),
  );
  getIt.registerLazySingleton<ArTransformationService>(
    () => ArTransformationService(),
  );

  // Auth Feature
  getIt.registerLazySingleton<AuthLocalDataSource>(
    () => AuthLocalDataSourceImpl(getIt()),
  );
  getIt.registerLazySingleton<AuthRemoteDataSource>(
    () => AuthRemoteDataSourceImpl(getIt()),
  );
  getIt.registerLazySingleton<AuthRepository>(
    () =>
        AuthRepositoryImpl(remoteDataSource: getIt(), localDataSource: getIt()),
  );
  getIt.registerLazySingleton(() => LoginUseCase(getIt()));
  getIt.registerLazySingleton(() => SignupUseCase(getIt()));
  getIt.registerLazySingleton(() => LogoutUseCase(getIt()));

  // Profile Feature
  getIt.registerLazySingleton<ProfileRemoteDataSource>(
    () => ProfileRemoteDataSourceImpl(getIt()),
  );
  getIt.registerLazySingleton<ProfileRepository>(
    () => ProfileRepositoryImpl(
      remoteDataSource: getIt(),
      authLocalDataSource: getIt(),
    ),
  );
  getIt.registerLazySingleton(() => GetMeUseCase(getIt()));

  getIt.registerFactory(
    () => AuthBloc(
      loginUseCase: getIt(),
      signupUseCase: getIt(),
      getMeUseCase: getIt(),
      logoutUseCase: getIt(),
    ),
  );

  // Camera Feature
  getIt.registerLazySingleton<CameraLocalDataSource>(
    () => CameraLocalDataSourceImpl(),
  );
  getIt.registerLazySingleton<CameraRemoteDataSource>(
    () => CameraRemoteDataSourceImpl(getIt()),
  );
  getIt.registerLazySingleton<CameraRepository>(
    () => CameraRepositoryImpl(
      localDataSource: getIt(),
      remoteDataSource: getIt(),
    ),
  );
  getIt.registerLazySingleton(() => CapturePhotoUseCase(getIt()));
  getIt.registerLazySingleton(() => UploadPhotoUseCase(getIt()));
  getIt.registerFactory(
    () => CameraBloc(capturePhotoUseCase: getIt(), uploadPhotoUseCase: getIt()),
  );

  // Destination Feature
  getIt.registerLazySingleton<DestinationRemoteDataSource>(
    () => DestinationRemoteDataSourceImpl(
      getIt(),
      getIt<LocationConfigService>(),
    ),
  );
  getIt.registerLazySingleton<DestinationRepository>(
    () => DestinationRepositoryImpl(
      remoteDataSource: getIt(),
      destinationsCacheService: getIt(),
      locationConfigService: getIt(),
    ),
  );
  getIt.registerLazySingleton(() => SearchDestinationsUseCase(getIt()));
  getIt.registerLazySingleton(() => SelectDestinationUseCase(getIt()));
  getIt.registerFactory(
    () => DestinationBloc(
      searchDestinationsUseCase: getIt(),
      selectDestinationUseCase: getIt(),
      recentDestinationsService: getIt(),
    ),
  );

  getIt.registerFactory(() => FloorMapBloc());

  // Navigation Feature
  getIt.registerLazySingleton<NavigationLocalDataSource>(
    () => NavigationLocalDataSourceImpl(),
  );
  getIt.registerLazySingleton<NavigationRemoteDataSource>(
    () => NavigationRemoteDataSourceImpl(getIt()),
  );
  getIt.registerLazySingleton<NavigationRepository>(
    () => NavigationRepositoryImpl(
      localDataSource: getIt(),
      remoteDataSource: getIt(),
    ),
  );
  getIt.registerLazySingleton(() => GetRouteUseCase(getIt()));
  getIt.registerFactory(
    () => NavigationBloc(
      getRouteUseCase: getIt(),
      getDestinationsUseCase: getIt(),
      locationConfigService: getIt(),
      floorPlanCacheService: getIt(),
      destinationsCacheService: getIt(),
      saveLocalizationHistoryUseCase: getIt(),
      deviceIdService: getIt(),
      arTrackingRepository: getIt(),
      spatialAudioRepository: getIt(),
      arTransformationService: getIt(),
    ),
  );

  // Locate Me Feature
  getIt.registerLazySingleton<LocateMeRemoteDataSource>(
    () => LocateMeRemoteDataSourceImpl(getIt()),
  );
  getIt.registerLazySingleton<LocateMeRepository>(
    () => LocateMeRepositoryImpl(remoteDataSource: getIt()),
  );
  getIt.registerLazySingleton(() => GetFloorPlanUseCase(getIt()));
  getIt.registerLazySingleton(() => LocalizeUserUseCase(getIt()));
  getIt.registerLazySingleton(() => GetDestinationsUseCase(getIt()));
  getIt.registerFactory(
    () => LocateMeBloc(
      getFloorPlanUseCase: getIt(),
      localizeUserUseCase: getIt(),
      getDestinationsUseCase: getIt(),
      locationConfigService: getIt(),
      floorPlanCacheService: getIt(),
      destinationsCacheService: getIt(),
      deviceIdService: getIt(),
    ),
  );

  // Theme
  getIt.registerLazySingleton<ThemeBloc>(() => ThemeBloc(getIt()));

  // Localization History Feature
  getIt.registerLazySingleton<LocalizationHistoryRemoteDataSource>(
    () => LocalizationHistoryRemoteDataSourceImpl(getIt()),
  );
  getIt.registerLazySingleton<LocalizationHistoryLocalDataSource>(
    () => LocalizationHistoryLocalDataSourceImpl(sharedPreferences: getIt()),
  );
  getIt.registerLazySingleton<LocalizationHistoryRepository>(
    () => LocalizationHistoryRepositoryImpl(
      remoteDataSource: getIt(),
      localDataSource: getIt(),
    ),
  );
  getIt.registerLazySingleton(
    () => GetUserLocalizationHistoryUseCase(repository: getIt()),
  );
  getIt.registerLazySingleton(
    () => SaveLocalizationHistoryUseCase(repository: getIt()),
  );
  getIt.registerFactory(
    () => LocalizationHistoryBloc(getUserLocalizationHistoryUseCase: getIt()),
  );
}
