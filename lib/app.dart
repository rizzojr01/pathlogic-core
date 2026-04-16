import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/constants/app_text.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/bloc/auth_event.dart';
import 'injection.dart';
import 'routes/app_router.dart';
import 'shared/widgets/fcm_banner_overlay.dart';
import 'theme/app_theme.dart';
import 'theme/theme_bloc.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => getIt<ThemeBloc>()..add(LoadTheme())),
        BlocProvider(
          create: (_) => getIt<AuthBloc>()..add(AuthCheckRequested()),
        ),
      ],
      child: BlocBuilder<ThemeBloc, ThemeState>(
        builder: (context, state) {
          return FcmBannerOverlay(
            child: MaterialApp.router(
              title: AppText.appName,
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(state.palette.scheme),
              darkTheme: AppTheme.light(
                state.palette.scheme,
              ), // Always use light theme
              themeMode: ThemeMode.light, // Force light theme
              routerConfig: AppRouter.router,
            ),
          );
        },
      ),
    );
  }
}
