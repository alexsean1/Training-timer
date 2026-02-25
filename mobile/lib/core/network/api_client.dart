import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants/api_constants.dart';
import '../security/secure_storage.dart';
import 'api_exception.dart';

/// Configured HTTP client wrapping Dio.
///
/// Features:
/// - Base URL, default JSON headers, and timeouts (connect: 10 s, receive: 30 s).
/// - Debug-only request/response logging via [_LoggingInterceptor].
/// - Auth interceptor that attaches Bearer tokens, silently refreshes on 401,
///   retries the original request, and calls [onSessionExpired] if refresh fails.
/// - Typed convenience methods ([get], [post], [put], [patch], [delete]) that
///   deserialise responses via a [fromJson] callback and throw [ApiException]
///   subtypes instead of raw [DioException].
///
/// Obtain the shared instance via `apiClientProvider` (in `providers.dart`).
class ApiClient {
  late final Dio dio;

  // Bare Dio used only for refresh calls so the auth interceptor
  // cannot fire on it and create an infinite loop.
  final Dio _refreshDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  ApiClient({required Future<void> Function() onSessionExpired}) {
    dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    if (kDebugMode) {
      dio.interceptors.add(_LoggingInterceptor());
    }

    dio.interceptors.add(_AuthInterceptor(
      authDio: dio,
      refreshDio: _refreshDio,
      onSessionExpired: onSessionExpired,
    ));
  }

  // ─── Typed request methods ─────────────────────────────────────────────────

  /// GET [path], deserialise with [fromJson].
  ///
  /// ```dart
  /// final user = await client.get(
  ///   '/api/v1/auth/me',
  ///   fromJson: (d) => AppUser.fromJson(d as Map<String, dynamic>),
  /// );
  /// ```
  Future<T> get<T>(
    String path, {
    required T Function(dynamic data) fromJson,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      _send(() => dio.get<dynamic>(path,
          queryParameters: queryParameters, options: options), fromJson);

  /// POST [path] with [data], deserialise with [fromJson].
  Future<T> post<T>(
    String path, {
    required T Function(dynamic data) fromJson,
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      _send(() => dio.post<dynamic>(path,
          data: data, queryParameters: queryParameters, options: options), fromJson);

  /// PUT [path] with [data], deserialise with [fromJson].
  Future<T> put<T>(
    String path, {
    required T Function(dynamic data) fromJson,
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      _send(() => dio.put<dynamic>(path,
          data: data, queryParameters: queryParameters, options: options), fromJson);

  /// PATCH [path] with [data], deserialise with [fromJson].
  Future<T> patch<T>(
    String path, {
    required T Function(dynamic data) fromJson,
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      _send(() => dio.patch<dynamic>(path,
          data: data, queryParameters: queryParameters, options: options), fromJson);

  /// DELETE [path], deserialise with [fromJson].
  ///
  /// For 204 No Content responses use `fromJson: (_) => null` with `T = void`.
  Future<T> delete<T>(
    String path, {
    required T Function(dynamic data) fromJson,
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      _send(() => dio.delete<dynamic>(path,
          data: data, queryParameters: queryParameters, options: options), fromJson);

  // ─── Internal ──────────────────────────────────────────────────────────────

  Future<T> _send<T>(
    Future<Response<dynamic>> Function() call,
    T Function(dynamic) fromJson,
  ) async {
    try {
      final response = await call();
      return fromJson(response.data);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}

// ─── Logging interceptor ──────────────────────────────────────────────────────

class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('[API] → ${options.method} ${options.uri}');
    if (options.data != null) debugPrint('[API]   ↑ ${options.data}');
    if (options.queryParameters.isNotEmpty) {
      debugPrint('[API]   ? ${options.queryParameters}');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    debugPrint('[API] ← ${response.statusCode} ${response.requestOptions.uri}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint('[API] ✗ ${err.response?.statusCode ?? 'ERR'} '
        '${err.requestOptions.uri}: ${err.message}');
    handler.next(err);
  }
}

// ─── Auth interceptor ─────────────────────────────────────────────────────────

class _AuthInterceptor extends Interceptor {
  final Dio authDio;
  final Dio refreshDio;
  final Future<void> Function() onSessionExpired;

  bool _isRefreshing = false;
  final List<({RequestOptions options, ErrorInterceptorHandler handler})>
      _pending = [];

  _AuthInterceptor({
    required this.authDio,
    required this.refreshDio,
    required this.onSessionExpired,
  });

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await SecureStorage.getAccessToken();
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401 ||
        _isAuthEndpoint(err.requestOptions)) {
      return handler.next(err);
    }

    if (_isRefreshing) {
      _pending.add((options: err.requestOptions, handler: handler));
      return;
    }

    _isRefreshing = true;
    try {
      final refreshToken = await SecureStorage.getRefreshToken();
      if (refreshToken == null) {
        return await _expireSession(err, handler);
      }

      final response = await refreshDio.post(
        '${ApiConstants.baseUrl}${ApiConstants.auth}/refresh',
        data: {'refresh_token': refreshToken},
      );
      final newAccess = response.data['access_token'] as String;
      final newRefresh = response.data['refresh_token'] as String;
      await SecureStorage.saveTokens(
          accessToken: newAccess, refreshToken: newRefresh);

      handler.resolve(await _retry(err.requestOptions, newAccess));
      for (final p in _pending) {
        try {
          p.handler.resolve(await _retry(p.options, newAccess));
        } catch (_) {}
      }
    } catch (_) {
      for (final p in _pending) {
        p.handler.next(err);
      }
      await _expireSession(err, handler);
    } finally {
      _pending.clear();
      _isRefreshing = false;
    }
  }

  Future<Response<dynamic>> _retry(RequestOptions options, String token) {
    options.headers['Authorization'] = 'Bearer $token';
    return authDio.fetch(options);
  }

  Future<void> _expireSession(
      DioException err, ErrorInterceptorHandler handler) async {
    await SecureStorage.clearTokens();
    await onSessionExpired();
    handler.next(err);
  }

  bool _isAuthEndpoint(RequestOptions options) {
    final path = options.path;
    return path.contains('/auth/login') ||
        path.contains('/auth/register') ||
        path.contains('/auth/refresh');
  }
}
