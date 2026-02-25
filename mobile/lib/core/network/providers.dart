import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import '../../features/auth/presentation/auth_notifier.dart';

/// The authenticated [ApiClient] singleton.
///
/// Shares the exact [ApiClient] instance owned by [AuthNotifier], so the token
/// refresh interceptor is active for every request made through this provider.
///
/// Feature repositories outside the auth domain should depend on this:
/// ```dart
/// class ProductRepository extends BaseRepository {
///   ProductRepository(Ref ref) : super(ref.watch(apiClientProvider));
/// }
///
/// final productRepoProvider = Provider((ref) => ProductRepository(ref));
/// ```
final apiClientProvider = Provider<ApiClient>((ref) {
  return ref.watch(authProvider).apiClient;
});
