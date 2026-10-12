import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/appearance.dart';
import 'core/router.dart';
import 'core/splash.dart';
import 'core/theme.dart';
import 'features/auth/data/auth_providers.dart';

void main() {
  runApp(const ProviderScope(child: GroupChatCourtApp()));
}

class GroupChatCourtApp extends ConsumerWidget {
  const GroupChatCourtApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themes = (light: courtLightTheme(), dark: courtDarkTheme());
    final mode = ref.watch(appearanceProvider);

    // Hold the whole app on a splash until we know whether anyone is signed
    // in. Mounting the router first would build a protected route behind the
    // gate for a frame or more — long enough for it to call the API without a
    // token and render an error.
    if (!ref.watch(authResolvedProvider)) {
      return MaterialApp(
        title: 'Group Chat Court',
        debugShowCheckedModeBanner: false,
        theme: themes.light,
        darkTheme: themes.dark,
        themeMode: mode,
        home: const SplashScreen(),
      );
    }

    return MaterialApp.router(
      title: 'Group Chat Court',
      debugShowCheckedModeBanner: false,
      theme: themes.light,
      darkTheme: themes.dark,
      themeMode: mode,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
