import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/data/auth_providers.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/cases/presentation/case_detail_screen.dart';
import '../features/cases/presentation/create_case_screen.dart';
import '../features/cases/presentation/dashboard_screen.dart';
import '../features/courts/presentation/courts_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/invitations/presentation/invite_screen.dart';
import '../features/records/presentation/rap_sheet_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/verdicts/presentation/verdict_screen.dart';
import 'models.dart';

/// Rebuilds the router's redirect whenever the sign-in state changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen(authControllerProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      // The app does not mount this router until auth has resolved (see
      // GroupChatCourtApp), so this only ever runs with a known answer.
      final signedIn = ref.read(isSignedInProvider);
      final atSignIn = state.matchedLocation == '/sign-in';

      if (!signedIn && !atSignIn) return '/sign-in';
      if (signedIn && atSignIn) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/sign-in',
        name: 'sign-in',
        builder: (_, __) => const SignInScreen(),
      ),
      GoRoute(
        path: '/',
        name: 'dashboard',
        builder: (_, __) => const DashboardScreen(),
        routes: [
          GoRoute(
            path: 'settings',
            name: 'settings',
            builder: (_, __) => const SettingsScreen(),
          ),
          GoRoute(
            path: 'courts',
            name: 'courts',
            builder: (_, __) => const CourtsScreen(),
            routes: [
              GoRoute(
                path: ':courtId',
                name: 'court-detail',
                builder: (_, state) => CourtDetailScreen(
                  courtId: state.pathParameters['courtId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'notifications',
            name: 'notifications',
            builder: (_, __) => const NotificationsScreen(),
          ),
          GoRoute(
            path: 'rap-sheet',
            name: 'rap-sheet',
            builder: (_, __) => const RapSheetScreen(),
          ),
          GoRoute(
            path: 'cases/new',
            name: 'create-case',
            builder: (_, state) =>
                CreateCaseScreen(courtId: state.uri.queryParameters['court']),
          ),
          GoRoute(
            path: 'cases/:caseId',
            name: 'case-detail',
            builder: (_, state) =>
                CaseDetailScreen(caseId: state.pathParameters['caseId']!),
            routes: [
              GoRoute(
                path: 'invite',
                name: 'case-invite',
                builder: (_, state) => InviteScreen(
                  caseId: state.pathParameters['caseId']!,
                  // Carries the one-time invite token from the create call.
                  created: state.extra as CaseDetail?,
                ),
              ),
              GoRoute(
                path: 'verdict',
                name: 'case-verdict',
                builder: (_, state) =>
                    VerdictScreen(caseId: state.pathParameters['caseId']!),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Lost in the courthouse')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🧭', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text(
                'No such courtroom: ${state.uri}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Back to the docket'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});
