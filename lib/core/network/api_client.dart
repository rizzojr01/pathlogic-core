import 'dart:io' show HttpClient, X509Certificate;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../error/exceptions.dart';
import '../utils/logger.dart';

class ApiClient {
  final Dio _dio;
  final AppLogger _logger;

  ApiClient({required String baseUrl, required AppLogger logger})
    : _logger = logger,
      _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 5),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      ) {
    _setupInterceptors();
    _setupCertificateBypass();
  }

  void updateBaseUrl(String newUrl) {
    _dio.options.baseUrl = newUrl;
    _logger.info('ApiClient: Base URL updated to: $newUrl');
  }

  void _setupCertificateBypass() {
    // Web uses the browser's fetch stack — no IOHttpClientAdapter, no cert bypass.
    if (kIsWeb) return;
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
        return client;
      },
    );
  }

  void _setupInterceptors() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          _logger.info('Request: ${options.method} ${options.path}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          _logger.info(
            'Response: ${response.statusCode} ${response.requestOptions.path}',
          );
          return handler.next(response);
        },
        onError: (error, handler) {
          _logger.error('Error: ${error.message}', error: error);
          return handler.next(error);
        },
      ),
    );
  }

  // Dio's browser adapter ignores Dio timeout options — enforce a client-side
  // ceiling here so web requests give up at 5 min instead of hanging forever
  // (upstream Cloudflare/Koyeb still caps first at ~100s if the server hangs).
  static const _clientTimeout = Duration(minutes: 5);

  Future<T> _run<T>(Future<Response<T>> Function() call) async {
    try {
      final response = await call().timeout(
        _clientTimeout,
        onTimeout: () => throw DioException.connectionTimeout(
          timeout: _clientTimeout,
          requestOptions: RequestOptions(path: ''),
        ),
      );
      return response.data as T;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _run<T>(() => _dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: options,
      ));

  Future<T> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _run<T>(() => _dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      ));

  Future<T> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _run<T>(() => _dio.put<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      ));

  Future<T> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _run<T>(() => _dio.patch<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      ));

  Future<T> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _run<T>(() => _dio.delete<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      ));

  AppException _handleError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NetworkException('Connection timeout');
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        // Always prefer the backend's own message. Only when the response has
        // no usable message do we fall back to a generic per-status message.
        final backendMsg = _extractBackendMessage(error.response?.data);
        return ServerException(backendMsg ?? _statusMessage(code), code);
      case DioExceptionType.cancel:
        return const NetworkException('Request cancelled');
      case DioExceptionType.connectionError:
        return NetworkException(
          error.message?.isNotEmpty == true
              ? error.message!
              : 'Connection error',
        );
      default:
        return NetworkException(error.message ?? 'Unexpected error');
    }
  }

  /// Pull a human-readable message the backend actually sent, or null if the
  /// body has none (empty, HTML error page, or non-string fields).
  String? _extractBackendMessage(dynamic data) {
    if (data is Map) {
      for (final key in const ['message', 'error', 'detail', 'details']) {
        final v = data[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }
    if (data is String) {
      final s = data.trim();
      // Ignore empty bodies and HTML error pages (not user-facing text).
      if (s.isEmpty || s.startsWith('<')) return null;
      return s;
    }
    return null;
  }

  /// Generic message for an HTTP status when the backend sent no message body.
  String _statusMessage(int? code) {
    switch (code) {
      case 400:
        return 'The request was invalid. Please check your input and try again.';
      case 401:
      case 403:
        return 'Your session has expired or you do not have permission. Please log in again.';
      case 404:
        return 'The requested resource could not be found.';
      case 408:
        return 'The request timed out. Please try again.';
      case 429:
        return 'Too many requests. Please wait a moment and try again.';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'The server had a problem processing this request. Please try again shortly.';
      default:
        return code != null
            ? 'Server error ($code). Please try again.'
            : 'Something went wrong. Please try again.';
    }
  }
}
