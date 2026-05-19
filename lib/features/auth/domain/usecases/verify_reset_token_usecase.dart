import 'package:dartz/dartz.dart';
import 'package:smart_sense/core/base/usecase.dart';
import 'package:smart_sense/core/error/failures.dart';
import 'package:smart_sense/features/auth/domain/repositories/auth_repository.dart';

class VerifyResetTokenUseCase
    implements UseCase<void, VerifyResetTokenParams> {
  final AuthRepository repository;

  VerifyResetTokenUseCase(this.repository);

  @override
  Future<Either<Failure, void>> call(VerifyResetTokenParams params) async {
    return await repository.verifyResetToken(
      email: params.email,
      token: params.token,
    );
  }
}

class VerifyResetTokenParams {
  final String email;
  final String token;

  VerifyResetTokenParams({
    required this.email,
    required this.token,
  });
}
