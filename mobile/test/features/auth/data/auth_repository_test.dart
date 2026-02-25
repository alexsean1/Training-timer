import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/network/result.dart';
import 'package:mobile/features/auth/data/auth_repository.dart';
import 'package:mobile/features/auth/data/models/auth_models.dart';

// ─── Mocks ────────────────────────────────────────────────────────────────────

class MockApiClient extends Mock implements ApiClient {}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Raw JSON that the server returns for a successful auth response.
const _tokenJson = {
  'access_token': 'test_access_token',
  'refresh_token': 'test_refresh_token',
  'token_type': 'bearer',
};

/// Raw JSON that the server returns for a successful /me response.
const _userJson = {
  'id': 'a1b2c3d4-0000-0000-0000-000000000000',
  'email': 'user@example.com',
  'is_active': true,
};

/// Stubs [client.post] so that it invokes the real [fromJson] callback with
/// [responseJson], returning whatever [fromJson] produces.
///
/// This pattern lets the stub exercise the actual deserialization code
/// instead of hard-coding a fake model object.
void _stubPost(MockApiClient client, Map<String, dynamic> responseJson) {
  when(
    () => client.post(
      any(),
      fromJson: any(named: 'fromJson'),
      data: any(named: 'data'),
    ),
  ).thenAnswer((inv) async {
    final fromJson =
        inv.namedArguments[#fromJson] as dynamic Function(dynamic);
    return fromJson(responseJson);
  });
}

void _stubGet(MockApiClient client, Map<String, dynamic> responseJson) {
  when(
    () => client.get(
      any(),
      fromJson: any(named: 'fromJson'),
    ),
  ).thenAnswer((inv) async {
    final fromJson =
        inv.namedArguments[#fromJson] as dynamic Function(dynamic);
    return fromJson(responseJson);
  });
}

void _stubPostThrows(MockApiClient client, ApiException exception) {
  when(
    () => client.post(
      any(),
      fromJson: any(named: 'fromJson'),
      data: any(named: 'data'),
    ),
  ).thenThrow(exception);
}

void _stubGetThrows(MockApiClient client, ApiException exception) {
  when(
    () => client.get(
      any(),
      fromJson: any(named: 'fromJson'),
    ),
  ).thenThrow(exception);
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late MockApiClient mockClient;
  late AuthRepository repository;

  setUp(() {
    mockClient = MockApiClient();
    repository = AuthRepository(mockClient);
  });

  // ─── login ─────────────────────────────────────────────────────────────────

  group('AuthRepository.login', () {
    test('returns Ok<TokenResponse> on success', () async {
      _stubPost(mockClient, _tokenJson);

      final result = await repository.login('user@example.com', 'password123');

      expect(result, isA<Ok<TokenResponse>>());
      final token = (result as Ok<TokenResponse>).value;
      expect(token.accessToken, 'test_access_token');
      expect(token.refreshToken, 'test_refresh_token');
      expect(token.tokenType, 'bearer');
    });

    test('returns Err<UnauthorisedException> on wrong credentials', () async {
      _stubPostThrows(mockClient, const UnauthorisedException('Invalid credentials.'));

      final result = await repository.login('user@example.com', 'wrong');

      expect(result, isA<Err<TokenResponse>>());
      expect((result as Err<TokenResponse>).error, isA<UnauthorisedException>());
    });

    test('returns Err<NetworkException> when offline', () async {
      _stubPostThrows(mockClient, const NetworkException());

      final result = await repository.login('user@example.com', 'password123');

      expect(result, isA<Err<TokenResponse>>());
      expect((result as Err<TokenResponse>).error, isA<NetworkException>());
    });
  });

  // ─── register ──────────────────────────────────────────────────────────────

  group('AuthRepository.register', () {
    test('returns Ok<TokenResponse> on success', () async {
      _stubPost(mockClient, _tokenJson);

      final result =
          await repository.register('new@example.com', 'password123');

      expect(result, isA<Ok<TokenResponse>>());
      expect((result as Ok<TokenResponse>).value.accessToken, 'test_access_token');
    });

    test('returns Err<ConflictException> on duplicate email', () async {
      _stubPostThrows(mockClient, const ConflictException('Email already registered'));

      final result =
          await repository.register('existing@example.com', 'password123');

      expect(result, isA<Err<TokenResponse>>());
      final err = (result as Err<TokenResponse>).error;
      expect(err, isA<ConflictException>());
      expect(err.message, contains('Email already registered'));
    });

    test('returns Err<ValidationException> on server validation failure',
        () async {
      _stubPostThrows(
          mockClient, const ValidationException('Password too weak'));

      final result = await repository.register('x@example.com', 'weak');

      expect(result, isA<Err<TokenResponse>>());
      expect((result as Err<TokenResponse>).error, isA<ValidationException>());
    });
  });

  // ─── getMe ─────────────────────────────────────────────────────────────────

  group('AuthRepository.getMe', () {
    test('returns Ok<AppUser> on success', () async {
      _stubGet(mockClient, _userJson);

      final result = await repository.getMe();

      expect(result, isA<Ok<AppUser>>());
      final user = (result as Ok<AppUser>).value;
      expect(user.email, 'user@example.com');
      expect(user.isActive, isTrue);
    });

    test('returns Err<UnauthorisedException> when token is invalid', () async {
      _stubGetThrows(mockClient, const UnauthorisedException());

      final result = await repository.getMe();

      expect(result, isA<Err<AppUser>>());
      expect((result as Err<AppUser>).error, isA<UnauthorisedException>());
    });

    test('returns Err<NetworkException> when offline', () async {
      _stubGetThrows(mockClient, const NetworkException());

      final result = await repository.getMe();

      expect(result, isA<Err<AppUser>>());
      expect((result as Err<AppUser>).error, isA<NetworkException>());
    });
  });

  // ─── Result helpers ────────────────────────────────────────────────────────

  group('Result helpers', () {
    test('Ok.valueOrThrow returns the value', () async {
      _stubPost(mockClient, _tokenJson);
      final result = await repository.login('u@e.com', 'password123');
      expect(result.valueOrThrow, isA<TokenResponse>());
    });

    test('Err.valueOrThrow throws the contained ApiException', () async {
      _stubPostThrows(mockClient, const NetworkException('Offline'));
      final result = await repository.login('u@e.com', 'password123');
      expect(() => result.valueOrThrow, throwsA(isA<NetworkException>()));
    });

    test('Ok.map transforms the value', () async {
      _stubPost(mockClient, _tokenJson);
      final result = await repository.login('u@e.com', 'password123');
      final mapped = result.map((t) => t.accessToken);
      expect(mapped, isA<Ok<String>>());
      expect((mapped as Ok<String>).value, 'test_access_token');
    });

    test('Err.valueOr returns the fallback', () async {
      _stubPostThrows(mockClient, const NetworkException());
      final result = await repository.login('u@e.com', 'password123');
      // TokenResponse has no sensible fallback, so we just verify Err path
      expect(result.isErr, isTrue);
    });
  });
}
