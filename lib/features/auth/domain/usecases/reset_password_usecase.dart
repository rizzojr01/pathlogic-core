import 'package:dartz/dartz.dart';
import 'package:smart_sense/core/base/usecase.dart';
import 'package:smart_sense/core/error/failures.dart';
import 'package:smart_sense/features/auth/domain/repositories/auth_repository.dart';

class ResetPasswordParams {
  final String token;
  final String newPassword;

  ResetPasswordParams({
    required this.token,
    required this.newPassword,
  });
}

class ResetPasswordUseCase implements UseCase<void, ResetPasswordParams> {
  final AuthRepository repository;

  ResetPasswordUseCase(this.repository);

  @override
  Future<Either<Failure, void>> call(ResetPasswordParams params) async {
    return await repository.resetPassword(
      token: params.token,
      newPassword: params.newPassword,
    );
  }
}
