import 'package:flutter/foundation.dart' show kDebugMode;

/// Build-time configuration.
///
///   flutter run --dart-define=API_BASE_URL=https://api.example.com
class Env {
  const Env._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000', // Android emulator -> host machine
  );

  /// Where the web app lives, for links a player must open in a browser.
  ///
  ///   flutter run --dart-define=WEB_BASE_URL=https://court.example.com
  ///
  /// Defaults to the API host on the web dev server's port.
  static const _webBase = String.fromEnvironment('WEB_BASE_URL');
  static String get webBaseUrl {
    if (_webBase.isNotEmpty) return _webBase;
    final uri = Uri.parse(apiBaseUrl);
    return uri.replace(port: 5173).toString();
  }

  /// Log every API call. On in debug builds, off in release.
  ///
  ///   flutter run --dart-define=API_LOG=false     # silence it
  ///   flutter build apk --dart-define=API_LOG=true # force it on
  static const apiLog = bool.fromEnvironment(
    'API_LOG',
    defaultValue: kDebugMode,
  );
}
