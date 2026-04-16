import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/user_entity.dart';

abstract class ProfileRepository {
  Future<Either<Failure, UserEntity>> getMe();
}
