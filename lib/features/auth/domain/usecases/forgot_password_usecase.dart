import 'package:dartz/dartz.dart';
import 'package:smart_sense/core/base/usecase.dart';
import 'package:smart_sense/core/error/failures.dart';
import 'package:smart_sense/features/auth/domain/repositories/auth_repository.dart';

class ForgotPasswordParams {
  final String email;

  ForgotPasswordParams({required this.email});
}

class ForgotPasswordUseCase implements UseCase<void, ForgotPasswordParams> {
  final AuthRepository repository;

  ForgotPasswordUseCase(this.repository);

  @override
  Future<Either<Failure, void>> call(ForgotPasswordParams params) async {
    return await repository.forgotPassword(params.email);
  }
}
