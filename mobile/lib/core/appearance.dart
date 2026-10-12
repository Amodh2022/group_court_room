import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _appearanceKey = 'gcc.appearance';

/// Light, dark, or whatever the phone says.
///
/// Defaults to light: the courtroom is a bright design, and a phone that
/// happens to be in dark mode should not silently change what the app is. Dark
/// is a choice the person makes in Settings.
class AppearanceController extends StateNotifier<ThemeMode> {
  AppearanceController() : super(ThemeMode.light) {
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_appearanceKey);
      final mode = ThemeMode.values.where((m) => m.name == saved).firstOrNull;
      if (mode != null && mounted) state = mode;
    } catch (_) {
      // Storage unavailable: stay on the default rather than block the app.
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_appearanceKey, mode.name);
    } catch (_) {
      // The choice still applies for this session.
    }
  }
}

final appearanceProvider =
    StateNotifierProvider<AppearanceController, ThemeMode>(
      (ref) => AppearanceController(),
    );
