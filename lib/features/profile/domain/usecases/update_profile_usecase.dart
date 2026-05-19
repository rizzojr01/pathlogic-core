import 'package:dartz/dartz.dart';
import 'package:smart_sense/core/base/usecase.dart';
import 'package:smart_sense/core/error/failures.dart';
import 'package:smart_sense/features/profile/domain/entities/user_entity.dart';
import 'package:smart_sense/features/profile/domain/repositories/profile_repository.dart';

class UpdateProfileParams {
  final String? nickname;
  final String? phone;

  const UpdateProfileParams({
    this.nickname,
    this.phone,
  });
}

class UpdateProfileUseCase implements UseCase<UserEntity, UpdateProfileParams> {
  final ProfileRepository repository;

  UpdateProfileUseCase(this.repository);

  @override
  Future<Either<Failure, UserEntity>> call(UpdateProfileParams params) {
    return repository.updateProfile(
      nickname: params.nickname,
      phone: params.phone,
    );
  }
}
