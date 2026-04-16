import 'package:dartz/dartz.dart';
import '../../../../core/base/usecase.dart';
import '../../../../core/error/failures.dart';
import '../entities/auth_token_entity.dart';
import '../repositories/auth_repository.dart';

class SignupParams {
  final String email;
  final String nickname;
  final String password;

  SignupParams({
    required this.email,
    required this.nickname,
    required this.password,
  });
}

class SignupUseCase extends UseCase<AuthTokenEntity, SignupParams> {
  final AuthRepository repository;

  SignupUseCase(this.repository);

  @override
  Future<Either<Failure, AuthTokenEntity>> call(SignupParams params) async {
    return await repository.signup(
      email: params.email,
      nickname: params.nickname,
      password: params.password,
    );
  }
}
