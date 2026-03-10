import 'package:dio/dio.dart';

// ─── Exception hierarchy ───────────────────────────────────────────────────────

/// Base class for all API-level exceptions.
///
/// Use exhaustive switches on the concrete subtypes to handle each case:
/// ```dart
/// switch (exception) {
///   case NetworkException()    => showOfflineBanner();
///   case UnauthorisedException() => router.go('/login');
///   case ServerException(:final statusCode) => logError(statusCode);
///   ...
/// }
/// ```
sealed class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}

/// No internet connection or DNS resolution failure.
final class NetworkException extends ApiException {
  const NetworkException([super.message = 'No internet connection.']);
}

/// Request or response timed out.
final class TimeoutException extends ApiException {
  const TimeoutException([super.message = 'The request timed out.']);
}

/// 401 — token missing, invalid, or refresh failed.
final class UnauthorisedException extends ApiException {
  const UnauthorisedException(
      [super.message = 'Session expired. Please sign in again.']);
}

/// 403 — authenticated but not permitted to access the resource.
final class ForbiddenException extends ApiException {
  const ForbiddenException(
      [super.message =
          'You do not have permission to perform this action.']);
}

/// 404 — resource not found.
final class NotFoundException extends ApiException {
  const NotFoundException(
      [super.message = 'The requested resource was not found.']);
}

/// 409 — conflict, e.g. duplicate email on registration.
final class ConflictException extends ApiException {
  const ConflictException([super.message = 'Conflict.']);
}

/// 422 — server-side validation failed.
final class ValidationException extends ApiException {
  const ValidationException([super.message = 'Validation error.']);
}

/// 5xx — server-side error.
final class ServerException extends ApiException {
  final int? statusCode;
  const ServerException({String message = 'A server error occurred. Please try again later.', this.statusCode}) : super(message);
}

/// Catch-all for unexpected errors that do not fit any other category.
final class UnknownException extends ApiException {
  const UnknownException([super.message = 'An unexpected error occurred.']);
}

// ─── Mapping ──────────────────────────────────────────────────────────────────

/// Converts a [DioException] into the most specific [ApiException] subtype.
ApiException mapDioException(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return const TimeoutException();

    case DioExceptionType.connectionError:
      return const NetworkException();

    case DioExceptionType.badResponse:
      final code = e.response?.statusCode;
      if (code == null) return const NetworkException();
      final detail = _extractDetail(e.response?.data);
      return switch (code) {
        401 => UnauthorisedException(detail ?? 'Unauthorised.'),
        403 => ForbiddenException(detail ?? 'Forbidden.'),
        404 => NotFoundException(detail ?? 'Not found.'),
        409 => ConflictException(detail ?? 'Conflict.'),
        422 => ValidationException(detail ?? 'Validation error.'),
        int c when c >= 500 =>
          ServerException(message: detail ?? 'Server error.', statusCode: c),
        _ => UnknownException(detail ?? 'HTTP $code'),
      };

    default:
      return UnknownException(e.message ?? 'Unknown network error.');
  }
}

String? _extractDetail(dynamic data) {
  if (data is Map && data.containsKey('detail')) {
    return data['detail'].toString();
  }
  return null;
}
