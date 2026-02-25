import 'api_exception.dart';

/// A discriminated union that holds either a success value [Ok] or a typed
/// [ApiException] error [Err].
///
/// Use Dart 3 exhaustive switch for safe handling:
/// ```dart
/// switch (result) {
///   case Ok(:final value): print(value);
///   case Err(:final error): print(error.message);
/// }
/// ```
///
/// Or use the helpers for quick transformations:
/// ```dart
/// final name = result.valueOr('anonymous');
/// final upper = result.map((s) => s.toUpperCase());
/// ```
sealed class Result<T> {
  const Result();

  /// `true` if this is [Ok].
  bool get isOk => this is Ok<T>;

  /// `true` if this is [Err].
  bool get isErr => this is Err<T>;

  /// Returns the success value, or throws the contained [ApiException].
  T get valueOrThrow => switch (this) {
        Ok(:final value) => value,
        Err(:final error) => throw error,
      };

  /// Returns the success value, or [fallback] if this is [Err].
  T valueOr(T fallback) => switch (this) {
        Ok(:final value) => value,
        Err() => fallback,
      };

  /// Transforms the success value with [transform], leaving errors unchanged.
  Result<U> map<U>(U Function(T value) transform) => switch (this) {
        Ok(:final value) => Ok(transform(value)),
        Err(:final error) => Err(error),
      };

  /// Chains another [Result]-returning computation on success.
  /// Short-circuits and propagates the original error on [Err].
  Result<U> flatMap<U>(Result<U> Function(T value) transform) =>
      switch (this) {
        Ok(:final value) => transform(value),
        Err(:final error) => Err(error),
      };
}

/// Represents a successful result holding [value].
final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

/// Represents a failed result holding a typed [ApiException] as [error].
final class Err<T> extends Result<T> {
  final ApiException error;
  const Err(this.error);
}
