import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../features/splash/presentation/pages/splash_page.dart';
import '../features/onboarding/presentation/pages/onboarding_page.dart';
import '../features/auth/presentation/pages/login_page.dart';
import '../features/auth/presentation/pages/signup_page.dart';
import '../features/auth/presentation/pages/forgot_password_page.dart';
import '../features/auth/presentation/pages/reset_password_page.dart';
import '../features/dashboard/presentation/pages/dashboard_page.dart';
import '../features/camera/presentation/pages/camera_page.dart';
import '../features/location/presentation/pages/location_detection_page.dart';
import '../features/destination/presentation/pages/destination_page.dart';
import '../features/navigation/presentation/pages/navigation_page.dart';
import '../features/navigation/presentation/pages/route_overview_page.dart';
import '../features/profile/presentation/pages/profile_page.dart';
import '../features/profile/presentation/pages/personal_information_page.dart';
import '../features/destination/domain/entities/destination_entity.dart';
import '../features/camera/presentation/bloc/camera_bloc.dart';
import '../features/destination/presentation/bloc/destination_bloc.dart';
import '../features/navigation/presentation/bloc/navigation_bloc.dart';
import '../features/locate_me/presentation/pages/locate_me_camera_page.dart';
import '../features/locate_me/presentation/pages/locate_me_floor_plan_page.dart';
import '../features/locate_me/presentation/bloc/locate_me_bloc.dart';
import '../features/localization_history/presentation/pages/localization_history_page.dart';
import '../features/localization_history/presentation/bloc/localization_history_bloc.dart';
import '../injection.dart';
import '../features/destination/presentation/pages/floor_map_page.dart';

class AppRouter {
  static final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String dashboard = '/dashboard';
  static const String camera = '/camera';
  static const String locationDetection = '/location-detection';
  static const String destination = '/destination';
  static const String navigation = '/navigation';
  static const String routeOverview = '/route-overview';
  static const String profile = '/profile';
  static const String locateMe = '/locate-me';
  static const String localizationHistory = '/localization-history';
  static const String locateMeFloorPlan = '/locate-me/floor-plan';
  static const String floorMap = '/floor-map';
  static const String personalInformation = '/personal-information';

  static final GoRouter router = GoRouter(
    initialLocation: splash,
    observers: [routeObserver],
    routes: [
      GoRoute(path: splash, builder: (context, state) => const SplashPage()),
      GoRoute(
        path: onboarding,
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(path: login, builder: (context, state) => const LoginPage()),
      GoRoute(path: signup, builder: (context, state) => const SignupPage()),
      GoRoute(
        path: forgotPassword,
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: resetPassword,
        builder: (context, state) {
          final email = state.extra as String? ?? '';
          return ResetPasswordPage(email: email);
        },
      ),
      GoRoute(
        path: dashboard,
        builder: (context, state) => const DashboardPage(),
      ),
      GoRoute(
        path: camera,
        builder: (context, state) {
          final extra = state.extra;
          DestinationEntity? destination;
          Map<String, dynamic>? manualCoordinates;
          String? pickedFloor;

          if (extra is Map<String, dynamic>) {
            destination = extra['destination'] as DestinationEntity?;
            manualCoordinates =
                extra['manualCoordinates'] as Map<String, dynamic>?;
            pickedFloor = extra['pickedFloor'] as String?;
          } else if (extra is DestinationEntity) {
            destination = extra;
            pickedFloor = destination.floor;
          }

          return BlocProvider(
            create: (context) => getIt<CameraBloc>(),
            child: CameraPage(
              destination: destination,
              manualCoordinates: manualCoordinates,
              pickedFloor: pickedFloor,
            ),
          );
        },
      ),
      GoRoute(
        path: locationDetection,
        builder: (context, state) => const LocationDetectionPage(),
      ),
      GoRoute(
        path: destination,
        builder: (context, state) {
          return BlocProvider(
            create: (context) => getIt<DestinationBloc>(),
            child: const DestinationPage(),
          );
        },
      ),
      GoRoute(path: profile, builder: (context, state) => const ProfilePage()),
      GoRoute(
        path: personalInformation,
        builder: (context, state) => const PersonalInformationPage(),
      ),
      GoRoute(
        path: floorMap,
        builder: (context, state) => const FloorMapPage(),
      ),
      GoRoute(
        path: routeOverview,
        builder: (context, state) {
          final extra = state.extra;
          DestinationEntity? destination;
          String? imagePath;
          Map<String, dynamic>? userPickedCoordinates;
          String? pickedFloor;
          double? heading;

          if (extra is Map<String, dynamic>) {
            destination = extra['destination'] as DestinationEntity?;
            imagePath = extra['imagePath'] as String?;
            userPickedCoordinates =
                extra['manualCoordinates'] as Map<String, dynamic>?;
            pickedFloor = extra['pickedFloor'] as String?;
            heading = extra['heading'] as double?;
          } else if (extra is DestinationEntity) {
            destination = extra;
          }

          if (destination == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Error')),
              body: const Center(child: Text('Destination is required')),
            );
          }
          final bloc = getIt<NavigationBloc>();
          return BlocProvider.value(
            value: bloc,
            child: RouteOverviewPage(
              destination: destination,
              imagePath: imagePath,
              userPickedCoordinates: userPickedCoordinates,
              pickedFloor: pickedFloor,
              heading: heading,
            ),
          );
        },
      ),
      GoRoute(
        path: navigation,
        pageBuilder: (context, state) {
          final extra = state.extra;
          DestinationEntity? destination;
          String? imagePath;
          Map<String, dynamic>? userPickedCoordinates;
          String? pickedFloor;
          double? heading;
          NavigationBloc? existingBloc;
          double? freshHeadingAtStart;

          if (extra is Map<String, dynamic>) {
            destination = extra['destination'] as DestinationEntity?;
            imagePath = extra['imagePath'] as String?;
            userPickedCoordinates =
                extra['manualCoordinates'] as Map<String, dynamic>?;
            pickedFloor = extra['pickedFloor'] as String?;
            heading = extra['heading'] as double?;
            existingBloc = extra['existingBloc'] as NavigationBloc?;
            freshHeadingAtStart = extra['freshHeadingAtStart'] as double?;
          } else if (extra is DestinationEntity) {
            destination = extra;
          }

          Widget child;
          if (destination == null) {
            child = Scaffold(
              appBar: AppBar(title: const Text('Error')),
              body: const Center(child: Text('Destination is required')),
            );
          } else {
            final page = NavigationPage(
              destination: destination,
              imagePath: imagePath,
              userPickedCoordinates: userPickedCoordinates,
              pickedFloor: pickedFloor,
              heading: heading,
              skipInitialization: existingBloc != null,
              freshHeadingAtStart: freshHeadingAtStart,
            );
            child = existingBloc != null
                ? BlocProvider.value(value: existingBloc, child: page)
                : BlocProvider(
                    create: (_) => getIt<NavigationBloc>(),
                    child: page,
                  );
          }

          // Smooth fade-in transition — the zoom effect comes from the overview
          // page's MapView animation that runs just before this page appears.
          return CustomTransitionPage(
            key: state.pageKey,
            child: child,
            transitionDuration: const Duration(milliseconds: 450),
            reverseTransitionDuration: const Duration(milliseconds: 300),
            transitionsBuilder: (context, animation, _, child) {
              return FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                ),
                child: child,
              );
            },
          );
        },
      ),
      GoRoute(
        path: locateMe,
        builder: (context, state) {
          return BlocProvider(
            create: (context) => getIt<LocateMeBloc>(),
            child: const LocateMeCameraPage(),
          );
        },
      ),
      GoRoute(
        path: localizationHistory,
        builder: (context, state) {
          return BlocProvider(
            create: (context) => getIt<LocalizationHistoryBloc>(),
            child: const LocalizationHistoryPage(),
          );
        },
      ),
      GoRoute(
        path: locateMeFloorPlan, // Using the static const
        builder: (context, state) {
          final bloc = state.extra as LocateMeBloc;
          return BlocProvider.value(
            value: bloc,
            child: const LocateMeFloorPlanPage(),
          );
        },
      ),
    ],
  );
}
