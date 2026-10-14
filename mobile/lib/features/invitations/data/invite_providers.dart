import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models.dart';
import '../../auth/data/auth_providers.dart';

/// The charge behind a summons token.
///
/// Unauthenticated: the token is the capability, so this resolves whether or
/// not anybody is signed in — which is what lets the accused answer in the app
/// instead of being sent to a browser.
final invitePreviewProvider = FutureProvider.autoDispose
    .family<InvitePreview, String>((ref, token) async {
      final api = ref.watch(apiClientProvider);
      return api.invitePreview(token);
    });
