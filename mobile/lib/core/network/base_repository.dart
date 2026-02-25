import 'api_client.dart';
import 'api_exception.dart';
import 'result.dart';

/// Metadata for a paginated list response.
///
/// Compatible with the common server shape:
/// `{"items": [...], "total": N, "page": N, "page_size": N}`
///
/// A raw JSON array is also accepted and is treated as the only page.
class PaginatedResult<T> {
  final List<T> items;
  final int total;
  final int page;
  final int pageSize;

  const PaginatedResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  /// Whether more pages follow this one.
  bool get hasMore => (page * pageSize) < total;
}

/// Abstract base for all feature repositories.
///
/// Provides three building blocks:
///
/// 1. **[safeCall]** — wraps any API call and returns `Result<T>` instead of
///    throwing, mapping [ApiException] subtypes directly and catching any other
///    exception as [UnknownException].
///
/// 2. **[withRetry]** — retries transient failures ([NetworkException] and
///    [ServerException]) with exponential back-off, up to [maxAttempts] times.
///
/// 3. **[fetchPage]** — thin helper for paginated endpoints that passes
///    standard `page` / `page_size` query params and parses the response.
///
/// Usage:
/// ```dart
/// class UserRepository extends BaseRepository {
///   const UserRepository(super.client);
///
///   Future<Result<List<AppUser>>> getAll() =>
///       safeCall(() => client.get('/api/v1/users',
///           fromJson: (d) => (d as List)
///               .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
///               .toList()));
/// }
/// ```
abstract class BaseRepository {
  final ApiClient client;

  const BaseRepository(this.client);

  // ─── Error handling ─────────────────────────────────────────────────────────

  /// Executes [call] and wraps the result in a [Result].
  ///
  /// - [ApiException] subtype → captured as [Err].
  /// - Any other exception → wrapped in [UnknownException] as [Err].
  Future<Result<T>> safeCall<T>(Future<T> Function() call) async {
    try {
      return Ok(await call());
    } on ApiException catch (e) {
      return Err(e);
    } catch (e) {
      return Err(UnknownException(e.toString()));
    }
  }

  // ─── Retry ──────────────────────────────────────────────────────────────────

  /// Retries [call] up to [maxAttempts] times with exponential back-off.
  ///
  /// Only [NetworkException] and [ServerException] are retried; all other
  /// error types (auth, validation, not-found, etc.) are returned immediately
  /// because retrying them would be pointless.
  ///
  /// Back-off: [initialDelay], then ×2 on each subsequent attempt.
  ///
  /// ```dart
  /// final result = await withRetry(
  ///   () => safeCall(() => client.get('/api/v1/feed', fromJson: ...)),
  ///   maxAttempts: 3,
  /// );
  /// ```
  Future<Result<T>> withRetry<T>(
    Future<Result<T>> Function() call, {
    int maxAttempts = 3,
    Duration initialDelay = const Duration(milliseconds: 500),
  }) async {
    assert(maxAttempts >= 1, 'maxAttempts must be at least 1');

    var delay = initialDelay;
    Result<T>? lastResult;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      lastResult = await call();
      if (lastResult is Ok<T>) return lastResult;

      final error = (lastResult as Err<T>).error;
      final isRetryable =
          error is NetworkException || error is ServerException;

      if (!isRetryable || attempt == maxAttempts) return lastResult;

      await Future<void>.delayed(delay);
      delay = delay * 2; // Exponential back-off
    }

    return lastResult!;
  }

  // ─── Pagination ─────────────────────────────────────────────────────────────

  /// Fetches one page of results from [path].
  ///
  /// Sends `page` and `page_size` as query parameters. The server must return:
  /// - A JSON object `{"items": [...], "total": N, "page": N, "page_size": N}`, or
  /// - A raw JSON array (treated as the complete, single-page result).
  ///
  /// Additional query params can be supplied via [extraParams].
  Future<Result<PaginatedResult<T>>> fetchPage<T>({
    required String path,
    required T Function(Map<String, dynamic> json) fromJson,
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? extraParams,
  }) {
    return safeCall(() async {
      final data = await client.get<dynamic>(
        path,
        queryParameters: {
          'page': page,
          'page_size': pageSize,
          ...?extraParams,
        },
        fromJson: (d) => d,
      );

      if (data is List) {
        final items =
            data.map((e) => fromJson(e as Map<String, dynamic>)).toList();
        return PaginatedResult(
          items: items,
          total: items.length,
          page: page,
          pageSize: pageSize,
        );
      }

      final map = data as Map<String, dynamic>;
      return PaginatedResult(
        items: (map['items'] as List)
            .map((e) => fromJson(e as Map<String, dynamic>))
            .toList(),
        total: map['total'] as int,
        page: map['page'] as int,
        pageSize: map['page_size'] as int,
      );
    });
  }
}
