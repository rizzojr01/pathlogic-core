import 'package:smart_sense/core/network/api_client.dart';
import 'package:smart_sense/core/constants/api_routes.dart';
import '../models/auth_response_model.dart';

abstract class AuthRemoteDataSource {
  Future<AuthResponseModel> login({
    required String email,
    required String password,
  });

  Future<AuthResponseModel> signup({
    required String email,
    required String nickname,
    required String password,
  });

  Future<void> forgotPassword(String email);

  Future<void> verifyResetToken({
    required String email,
    required String token,
  });

  Future<void> resetPassword({
    required String email,
    required String token,
    required String newPassword,
  });
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final ApiClient apiClient;

  AuthRemoteDataSourceImpl(this.apiClient);

  @override
  Future<AuthResponseModel> login({
    required String email,
    required String password,
  }) async {
    final response = await apiClient.post(
      ApiRoutes.login,
      data: {'email': email, 'password': password},
    );
    return AuthResponseModel.fromJson(response as Map<String, dynamic>);
  }

  @override
  Future<AuthResponseModel> signup({
    required String email,
    required String nickname,
    required String password,
  }) async {
    final response = await apiClient.post(
      ApiRoutes.signup,
      data: {'email': email, 'nickname': nickname, 'password': password},
    );
    return AuthResponseModel.fromJson(response as Map<String, dynamic>);
  }

  @override
  Future<void> forgotPassword(String email) async {
    await apiClient.post(
      ApiRoutes.forgotPassword,
      data: {'email': email},
    );
  }

  @override
  Future<void> verifyResetToken({
    required String email,
    required String token,
  }) async {
    await apiClient.post(
      '/auth/verify-reset-token',
      data: {'email': email, 'token': token},
    );
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    await apiClient.post(
      ApiRoutes.resetPassword,
      data: {'email': email, 'token': token, 'new_password': newPassword},
    );
  }
}
