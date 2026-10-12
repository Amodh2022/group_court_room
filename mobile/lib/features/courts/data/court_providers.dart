import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models.dart';
import '../../auth/data/auth_providers.dart';

final courtsProvider = FutureProvider.autoDispose<List<Court>>((ref) async {
  ref.watch(authControllerProvider);
  return ref.watch(apiClientProvider).listCourts();
});

/// Cases somebody else filed that I was added to directly.
final sharedCasesProvider = FutureProvider.autoDispose<List<SharedCase>>((
  ref,
) async {
  ref.watch(authControllerProvider);
  return ref.watch(apiClientProvider).sharedCases();
});

final notificationsProvider = FutureProvider.autoDispose<NotificationFeed>((
  ref,
) async {
  ref.watch(authControllerProvider);
  return ref.watch(apiClientProvider).notifications();
});
