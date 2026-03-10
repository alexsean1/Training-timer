import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/result.dart';
import '../../../core/security/secure_storage.dart';
import '../data/auth_repository.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final String? error;

  const AuthState({required this.status, this.error});
}

/// Manages authentication state for the app.
///
/// Owns the single [ApiClient] instance so the token refresh interceptor is
/// wired to [handleSessionExpired]. The instance is exposed via [apiClient]
/// and shared as a Riverpod singleton through `apiClientProvider`
/// (see `core/network/providers.dart`).
class AuthNotifier extends ChangeNotifier {
  late final ApiClient _apiClient;
  late final AuthRepository _repository;

  AuthState _state = const AuthState(status: AuthStatus.initial);
  AuthState get state => _state;
  
  bool _disposed = false;

  /// The [ApiClient] used for all authenticated requests.
  ///
  /// Exposed so `apiClientProvider` in `providers.dart` can share this
  /// instance with non-auth feature repositories without creating a second
  /// client (and a second interceptor).
  ApiClient get apiClient => _apiClient;

  AuthNotifier() {
    _apiClient = ApiClient(onSessionExpired: handleSessionExpired);
    _repository = AuthRepository(_apiClient);
    _checkStoredSession();
  }

  /// Creates an [AuthNotifier] in the [AuthStatus.unauthenticated] state
  /// without reading from secure storage.
  ///
  /// Intended for use in widget tests via [FakeAuthNotifier]:
  /// ```dart
  /// class FakeAuthNotifier extends AuthNotifier {
  ///   FakeAuthNotifier() : super.unauthenticated();
  /// }
  /// ```
  @visibleForTesting
  AuthNotifier.unauthenticated() {
    _apiClient = ApiClient(onSessionExpired: handleSessionExpired);
    _repository = AuthRepository(_apiClient);
    _state = const AuthState(status: AuthStatus.unauthenticated);
  }

  // ─── Initialisation ─────────────────────────────────────────────────────────

  Future<void> _checkStoredSession() async {
    final token = await SecureStorage.getAccessToken();
    if (_disposed) return;
    _state = AuthState(
      status:
          token != null ? AuthStatus.authenticated : AuthStatus.unauthenticated,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ─── Session expiry (called by ApiClient interceptor) ───────────────────────

  /// Called by the [ApiClient] when a token refresh fails.
  ///
  /// Marks the session as unauthenticated, which causes [authProvider]'s
  /// listeners (including go_router) to redirect to the login screen.
  Future<void> handleSessionExpired() async {
    if (_disposed) return;
    _state = const AuthState(status: AuthStatus.unauthenticated);
    notifyListeners();
  }

  // ─── Auth actions ────────────────────────────────────────────────────────────

  Future<void> login(String email, String password) async {
    _state = const AuthState(status: AuthStatus.loading);
    notifyListeners();

    final result = await _repository.login(email, password);
    switch (result) {
      case Ok(:final value):
        await SecureStorage.saveTokens(
          accessToken: value.accessToken,
          refreshToken: value.refreshToken,
        );
        _state = const AuthState(status: AuthStatus.authenticated);
      case Err(:final error):
        _state = AuthState(
          status: AuthStatus.unauthenticated,
          error: error.message,
        );
    }
    notifyListeners();
  }

  Future<void> register(String email, String password) async {
    _state = const AuthState(status: AuthStatus.loading);
    notifyListeners();

    final result = await _repository.register(email, password);
    switch (result) {
      case Ok(:final value):
        await SecureStorage.saveTokens(
          accessToken: value.accessToken,
          refreshToken: value.refreshToken,
        );
        _state = const AuthState(status: AuthStatus.authenticated);
      case Err(:final error):
        _state = AuthState(
          status: AuthStatus.unauthenticated,
          error: error.message,
        );
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await SecureStorage.clearTokens();
    _state = const AuthState(status: AuthStatus.unauthenticated);
    notifyListeners();
  }
}

final authProvider =
    ChangeNotifierProvider<AuthNotifier>((ref) => AuthNotifier());
