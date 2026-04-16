import '../../../profile/data/models/user_model.dart';
import '../../domain/entities/auth_token_entity.dart';

class AuthResponseModel extends AuthTokenEntity {
  const AuthResponseModel({
    required super.accessToken,
    required super.tokenType,
    required super.user,
  });

  factory AuthResponseModel.fromJson(Map<String, dynamic> json) {
    return AuthResponseModel(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String,
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'token_type': tokenType,
      'user': (user as UserModel).toJson(),
    };
  }
}
