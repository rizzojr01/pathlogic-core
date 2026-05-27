import 'package:smart_sense/core/base/base_event.dart';

abstract class AuthEvent extends BaseEvent {}

class LoginSubmitted extends AuthEvent {
  final String email;
  final String password;

  LoginSubmitted({required this.email, required this.password});

  @override
  List<Object?> get props => [email, password];
}

class SignupSubmitted extends AuthEvent {
  final String email;
  final String nickname;
  final String password;

  SignupSubmitted({
    required this.email,
    required this.nickname,
    required this.password,
  });

  @override
  List<Object?> get props => [email, nickname, password];
}

class AuthLogoutRequested extends AuthEvent {
  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {
  @override
  List<Object?> get props => [];
}

class ForgotPasswordSubmitted extends AuthEvent {
  final String email;

  ForgotPasswordSubmitted({required this.email});

  @override
  List<Object?> get props => [email];
}

class VerifyResetTokenSubmitted extends AuthEvent {
  final String email;
  final String token;

  VerifyResetTokenSubmitted({required this.email, required this.token});

  @override
  List<Object?> get props => [email, token];
}

class ResetPasswordSubmitted extends AuthEvent {
  final String email;
  final String token;
  final String newPassword;

  ResetPasswordSubmitted({required this.email, required this.token, required this.newPassword});

  @override
  List<Object?> get props => [email, token, newPassword];
}

class AuthUpdateProfileSubmitted extends AuthEvent {
  final String? nickname;
  final String? phone;

  AuthUpdateProfileSubmitted({this.nickname, this.phone});

  @override
  List<Object?> get props => [nickname, phone];
}
