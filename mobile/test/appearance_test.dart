import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_chat_court/core/appearance.dart';
import 'package:group_chat_court/features/auth/data/auth_providers.dart';
import 'package:group_chat_court/features/settings/presentation/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('is light by default, whatever the phone is set to', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(appearanceProvider), ThemeMode.light);
  });

  test('remembers the choice across launches', () async {
    final first = ProviderContainer();
    await first.read(appearanceProvider.notifier).set(ThemeMode.dark);
    first.dispose();

    final second = ProviderContainer();
    addTearDown(second.dispose);
    second.read(appearanceProvider); // starts the restore
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(second.read(appearanceProvider), ThemeMode.dark);
  });

  test('ignores a stored value it does not recognise', () async {
    SharedPreferences.setMockInitialValues({'gcc.appearance': 'sepia'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appearanceProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(container.read(appearanceProvider), ThemeMode.light);
  });

  testWidgets('can be changed from settings', (tester) async {
    useMobileSurface(tester);
    final api = FakeApiClient();
    late ProviderContainer container;
    await tester.pumpWidget(
      harness(
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const SettingsScreen();
          },
        ),
        overrides: [apiClientProvider.overrideWithValue(api)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);
    expect(container.read(appearanceProvider), ThemeMode.light);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(container.read(appearanceProvider), ThemeMode.dark);

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(container.read(appearanceProvider), ThemeMode.system);
  });
}
