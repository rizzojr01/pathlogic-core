import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../auth/data/datasources/auth_local_datasource.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/profile_repository.dart';
import '../datasources/profile_remote_datasource.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  final ProfileRemoteDataSource remoteDataSource;
  final AuthLocalDataSource authLocalDataSource;

  ProfileRepositoryImpl({
    required this.remoteDataSource,
    required this.authLocalDataSource,
  });

  @override
  Future<Either<Failure, UserEntity>> getMe() async {
    try {
      final token = authLocalDataSource.getToken();
      if (token == null) {
        return const Left<Failure, UserEntity>(
          CacheFailure('Not authenticated'),
        );
      }
      final user = await remoteDataSource.getMe(token);
      await authLocalDataSource.saveUser(user);
      return Right<Failure, UserEntity>(user);
    } catch (e) {
      return Left<Failure, UserEntity>(ServerFailure(e.toString()));
    }
  }
}
