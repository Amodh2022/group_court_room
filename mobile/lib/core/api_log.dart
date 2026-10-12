import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Replaces anything secret before it is written to a log.
///
/// Logs end up in terminals, bug reports and screenshots. A bearer token or a
/// capability link pasted from one of those is a working credential, so these
/// are masked at the source rather than trusted to be handled carefully later.
class LogRedactor {
  const LogRedactor._();

  static const mask = '•••';

  /// Keys whose values are never printed, however they are nested.
  static final _secretKey = RegExp(
    r'token|authorization|password|secret|cookie',
    caseSensitive: false,
  );

  /// Capability links: invite (`inv_`), jury (`jry_`) and share (`shr_`). Keeps
  /// the prefix and the first characters, which is enough to tell two apart.
  static final _link = RegExp(
    r'\b(inv|jry|shr)_([A-Za-z0-9_-]{4})[A-Za-z0-9_-]{4,}',
  );

  static String text(String value) =>
      value.replaceAllMapped(_link, (m) => '${m[1]}_${m[2]}…');

  static Object? value(Object? node) {
    if (node is Map) {
      return {
        for (final entry in node.entries)
          entry.key: _secretKey.hasMatch('${entry.key}')
              ? mask
              : value(entry.value),
      };
    }
    if (node is List) return node.map(value).toList();
    if (node is String) return text(node);
    return node;
  }

  /// A body, redacted and cut to [max] characters so one big verdict cannot
  /// bury the rest of the log.
  static String body(Object? data, {int max = 1200}) {
    if (data == null) return '';
    final Object? safe = data is FormData ? '<form data>' : value(data);
    String out;
    try {
      out = safe is String ? safe : jsonEncode(safe);
    } catch (_) {
      out = '$safe';
    }
    return out.length <= max
        ? out
        : '${out.substring(0, max)}… (+${out.length - max} chars)';
  }

  static Map<String, dynamic> headers(Map<String, dynamic> headers) => {
    for (final entry in headers.entries)
      entry.key: _secretKey.hasMatch(entry.key) ? mask : entry.value,
  };
}

/// Logs every Dio request, its response and how long it took.
///
/// One line per event, easy to follow in `flutter run`:
///
///     → POST /api/v1/cases
///       body: {"title":"The Last Pizza Slice",...}
///     ← 201 POST /api/v1/cases (143 ms)
///       body: {"id":"…","jury_token":"•••",...}
///     ✖ GET /api/v1/cases (20012 ms) receiveTimeout: …
class ApiLogInterceptor extends Interceptor {
  ApiLogInterceptor({
    void Function(String line)? sink,
    this.maxBody = 1200,
    this.logHeaders = false,
  }) : sink = sink ?? _print;

  static void _print(String line) => debugPrint(line);

  /// Where lines go. Replaced in tests.
  final void Function(String line) sink;
  final int maxBody;

  /// Headers are noisy; off unless you are debugging one.
  final bool logHeaders;

  static const _startedKey = '_apiLogStarted';

  String _target(RequestOptions o) =>
      '${o.method} ${o.uri.path}'
      '${o.uri.hasQuery ? '?${LogRedactor.text(o.uri.query)}' : ''}';

  String _elapsed(RequestOptions o) {
    final started = o.extra[_startedKey] as int?;
    if (started == null) return '';
    final ms = DateTime.now().millisecondsSinceEpoch - started;
    return ' ($ms ms)';
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedKey] = DateTime.now().millisecondsSinceEpoch;
    sink('→ ${LogRedactor.text(_target(options))}');
    if (logHeaders) {
      sink('  headers: ${jsonEncode(LogRedactor.headers(options.headers))}');
    }
    final body = LogRedactor.body(options.data, max: maxBody);
    if (body.isNotEmpty) sink('  body: $body');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final o = response.requestOptions;
    final status = response.statusCode ?? 0;
    // A non-2xx still arrives here (the client maps statuses itself), so mark
    // failures the way a reader scanning the log would look for them.
    final mark = status >= 200 && status < 300 ? '←' : '⚠';
    sink('$mark $status ${LogRedactor.text(_target(o))}${_elapsed(o)}');
    final body = LogRedactor.body(response.data, max: maxBody);
    if (body.isNotEmpty) sink('  body: $body');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final o = err.requestOptions;
    sink(
      '✖ ${LogRedactor.text(_target(o))}${_elapsed(o)} ${err.type.name}: '
      '${LogRedactor.text('${err.message ?? err.error ?? ''}')}',
    );
    handler.next(err);
  }
}
