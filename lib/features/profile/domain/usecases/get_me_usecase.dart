import 'package:dartz/dartz.dart';
import '../../../../core/base/usecase.dart';
import '../../../../core/error/failures.dart';
import '../entities/user_entity.dart';
import '../repositories/profile_repository.dart';

class GetMeUseCase extends UseCase<UserEntity, NoParams> {
  final ProfileRepository repository;

  GetMeUseCase(this.repository);

  @override
  Future<Either<Failure, UserEntity>> call(NoParams params) async {
    return await repository.getMe();
  }
}
