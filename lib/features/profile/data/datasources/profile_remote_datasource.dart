import 'package:dio/dio.dart';
import 'package:smart_sense/core/network/api_client.dart';
import 'package:smart_sense/core/constants/api_routes.dart';
import '../models/user_model.dart';

abstract class ProfileRemoteDataSource {
  Future<UserModel> getMe(String token);
  Future<UserModel> updateProfile({
    required String token,
    String? nickname,
    String? phone,
  });
}

class ProfileRemoteDataSourceImpl implements ProfileRemoteDataSource {
  final ApiClient apiClient;

  ProfileRemoteDataSourceImpl(this.apiClient);

  @override
  Future<UserModel> getMe(String token) async {
    final response = await apiClient.get(
      ApiRoutes.me,
      options: Options(
        headers: {ApiRoutes.authHeader: '${ApiRoutes.bearerPrefix}$token'},
      ),
    );
    return UserModel.fromJson(response as Map<String, dynamic>);
  }

  @override
  Future<UserModel> updateProfile({
    required String token,
    String? nickname,
    String? phone,
  }) async {
    final Map<String, dynamic> data = {};
    if (nickname != null) data['nickname'] = nickname;
    if (phone != null) data['phone'] = phone;

    final response = await apiClient.patch(
      ApiRoutes.me,
      data: data,
      options: Options(
        headers: {ApiRoutes.authHeader: '${ApiRoutes.bearerPrefix}$token'},
      ),
    );
    return UserModel.fromJson(response as Map<String, dynamic>);
  }
}
