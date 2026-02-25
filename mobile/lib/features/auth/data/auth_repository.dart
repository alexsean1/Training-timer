import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/base_repository.dart';
import '../../../core/network/result.dart';
import 'models/auth_models.dart';

/// Repository for authentication endpoints.
///
/// Extends [BaseRepository] so every method returns `Result<T>` — callers
/// use exhaustive switch expressions instead of raw try/catch:
///
/// ```dart
/// final result = await repo.login(email, password);
/// switch (result) {
///   case Ok(:final value): // save tokens, navigate home
///   case Err(:final error): // show error.message in the UI
/// }
/// ```
class AuthRepository extends BaseRepository {
  const AuthRepository(ApiClient client) : super(client);

  Future<Result<TokenResponse>> login(String email, String password) =>
      safeCall(() => client.post(
            '${ApiConstants.auth}/login',
            data: {'email': email, 'password': password},
            fromJson: (d) => TokenResponse.fromJson(d as Map<String, dynamic>),
          ));

  Future<Result<TokenResponse>> register(String email, String password) =>
      safeCall(() => client.post(
            '${ApiConstants.auth}/register',
            data: {'email': email, 'password': password},
            fromJson: (d) => TokenResponse.fromJson(d as Map<String, dynamic>),
          ));

  Future<Result<AppUser>> getMe() => safeCall(() => client.get(
        '${ApiConstants.auth}/me',
        fromJson: (d) => AppUser.fromJson(d as Map<String, dynamic>),
      ));
}
