import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_sense/core/base/usecase.dart';
import 'package:smart_sense/features/profile/domain/usecases/get_me_usecase.dart';
import 'package:smart_sense/features/auth/domain/usecases/login_usecase.dart';
import 'package:smart_sense/features/auth/domain/usecases/logout_usecase.dart';
import 'package:smart_sense/features/auth/domain/usecases/signup_usecase.dart';
import 'package:smart_sense/features/auth/domain/usecases/forgot_password_usecase.dart';
import 'package:smart_sense/features/auth/domain/usecases/reset_password_usecase.dart';
import 'package:smart_sense/features/auth/domain/usecases/verify_reset_token_usecase.dart';
import 'package:smart_sense/features/profile/domain/usecases/update_profile_usecase.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final LoginUseCase loginUseCase;
  final SignupUseCase signupUseCase;
  final GetMeUseCase getMeUseCase;
  final LogoutUseCase logoutUseCase;
  final ForgotPasswordUseCase forgotPasswordUseCase;
  final VerifyResetTokenUseCase verifyResetTokenUseCase;
  final ResetPasswordUseCase resetPasswordUseCase;
  final UpdateProfileUseCase updateProfileUseCase;

  AuthBloc({
    required this.loginUseCase,
    required this.signupUseCase,
    required this.getMeUseCase,
    required this.logoutUseCase,
    required this.forgotPasswordUseCase,
    required this.verifyResetTokenUseCase,
    required this.resetPasswordUseCase,
    required this.updateProfileUseCase,
  }) : super(AuthInitial()) {
    on<LoginSubmitted>(_onLoginSubmitted);
    on<SignupSubmitted>(_onSignupSubmitted);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<ForgotPasswordSubmitted>(_onForgotPasswordSubmitted);
    on<VerifyResetTokenSubmitted>(_onVerifyResetTokenSubmitted);
    on<ResetPasswordSubmitted>(_onResetPasswordSubmitted);
    on<AuthUpdateProfileSubmitted>(_onAuthUpdateProfileSubmitted);
  }

  Future<void> _onLoginSubmitted(
    LoginSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    final result = await loginUseCase(
      LoginParams(email: event.email, password: event.password),
    );
    result.fold(
      (failure) => emit(AuthFailure(message: failure.message)),
      (authToken) => emit(Authenticated(user: authToken.user)),
    );
  }

  Future<void> _onSignupSubmitted(
    SignupSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    final result = await signupUseCase(
      SignupParams(
        email: event.email,
        nickname: event.nickname,
        password: event.password,
      ),
    );
    result.fold(
      (failure) => emit(AuthFailure(message: failure.message)),
      (authToken) => emit(Authenticated(user: authToken.user)),
    );
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    final result = await logoutUseCase(NoParams());
    result.fold(
      (failure) => emit(AuthFailure(message: failure.message)),
      (_) => emit(Unauthenticated()),
    );
  }

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    final result = await getMeUseCase(NoParams());
    result.fold(
      (failure) => emit(Unauthenticated()),
      (user) => emit(Authenticated(user: user)),
    );
  }

  Future<void> _onForgotPasswordSubmitted(
    ForgotPasswordSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthActionLoading());
    final result = await forgotPasswordUseCase(
      ForgotPasswordParams(email: event.email),
    );
    result.fold(
      (failure) => emit(AuthFailure(message: failure.message)),
      (_) => emit(ForgotPasswordSuccess()),
    );
  }

  Future<void> _onVerifyResetTokenSubmitted(
    VerifyResetTokenSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthActionLoading());
    final result = await verifyResetTokenUseCase(
      VerifyResetTokenParams(email: event.email, token: event.token),
    );
    result.fold(
      (failure) => emit(AuthFailure(message: failure.message)),
      (_) => emit(ResetTokenVerified()),
    );
  }

  Future<void> _onResetPasswordSubmitted(
    ResetPasswordSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthActionLoading());
    final result = await resetPasswordUseCase(
      ResetPasswordParams(
        email: event.email,
        token: event.token,
        newPassword: event.newPassword,
      ),
    );
    result.fold(
      (failure) => emit(AuthFailure(message: failure.message)),
      (_) => emit(ResetPasswordSuccess()),
    );
  }

  Future<void> _onAuthUpdateProfileSubmitted(
    AuthUpdateProfileSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthActionLoading());
    final result = await updateProfileUseCase(
      UpdateProfileParams(
        nickname: event.nickname,
        phone: event.phone,
      ),
    );
    result.fold(
      (failure) => emit(AuthFailure(message: failure.message)),
      (user) => emit(Authenticated(user: user)),
    );
  }
}
