import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_chat_court/core/api_log.dart';

/// Answers every request with a canned response, or throws.
class _Adapter implements HttpClientAdapter {
  _Adapter({this.status = 200, this.body = const {}, this.error});

  final int status;
  final Object body;
  final DioException Function(RequestOptions)? error;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (error != null) throw error!(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

({Dio dio, List<String> lines}) _client(
  _Adapter adapter, {
  bool logHeaders = false,
  int maxBody = 1200,
}) {
  final lines = <String>[];
  final dio =
      Dio(BaseOptions(baseUrl: 'http://api.test', validateStatus: (_) => true))
        ..httpClientAdapter = adapter
        ..interceptors.add(
          ApiLogInterceptor(
            sink: lines.add,
            logHeaders: logHeaders,
            maxBody: maxBody,
          ),
        );
  return (dio: dio, lines: lines);
}

void main() {
  group('a successful call', () {
    test(
      'logs the request, then the response with its status and timing',
      () async {
        final c = _client(_Adapter(status: 201, body: {'id': 'abc'}));
        await c.dio.post(
          '/api/v1/cases',
          data: {'title': 'The Last Pizza Slice'},
        );

        expect(c.lines[0], '→ POST /api/v1/cases');
        expect(c.lines[1], '  body: {"title":"The Last Pizza Slice"}');
        expect(
          c.lines[2],
          matches(RegExp(r'^← 201 POST /api/v1/cases \(\d+ ms\)$')),
        );
        expect(c.lines[3], '  body: {"id":"abc"}');
      },
    );

    test('logs a body-less GET without an empty body line', () async {
      final c = _client(_Adapter(body: <String, dynamic>{}));
      await c.dio.get('/api/v1/cases', queryParameters: {'limit': 5});

      expect(c.lines.first, '→ GET /api/v1/cases?limit=5');
      expect(
        c.lines.where((l) => l.startsWith('  body: ') && l == '  body: '),
        isEmpty,
      );
    });
  });

  group('failures', () {
    test('marks a non-2xx response so it stands out in a scan', () async {
      // The client maps statuses itself (validateStatus accepts everything), so
      // a 409 is a response, not an exception. It must still look like a problem.
      final c = _client(
        _Adapter(status: 409, body: {'message': 'Too many open cases.'}),
      );
      await c.dio.post('/api/v1/cases', data: {});

      expect(
        c.lines.any((l) => l.startsWith('⚠ 409 POST /api/v1/cases')),
        isTrue,
      );
      expect(c.lines.last, contains('Too many open cases.'));
    });

    test('logs a network failure with its type and how long it took', () async {
      final c = _client(
        _Adapter(
          error: (o) => DioException(
            requestOptions: o,
            type: DioExceptionType.receiveTimeout,
            message: 'took too long',
          ),
        ),
      );

      await expectLater(
        c.dio.get('/api/v1/cases'),
        throwsA(isA<DioException>()),
      );
      final line = c.lines.last;
      expect(line, startsWith('✖ GET /api/v1/cases'));
      expect(line, contains('receiveTimeout'));
      expect(line, contains('took too long'));
      expect(line, matches(RegExp(r'\(\d+ ms\)')));
    });

    test('still lets the error reach the caller unchanged', () async {
      final c = _client(
        _Adapter(
          error: (o) => DioException(
            requestOptions: o,
            type: DioExceptionType.connectionError,
          ),
        ),
      );
      await expectLater(
        c.dio.get('/x'),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.connectionError,
          ),
        ),
      );
    });
  });

  group('secrets never reach the log', () {
    test('masks the bearer token when headers are logged', () async {
      final c = _client(_Adapter(), logHeaders: true);
      await c.dio.get(
        '/api/v1/cases',
        options: Options(headers: {'Authorization': 'Bearer super-secret-jwt'}),
      );

      final all = c.lines.join('\\n');
      expect(all, contains('"Authorization":"•••"'));
      expect(all, isNot(contains('super-secret-jwt')));
    });

    test('omits headers entirely by default', () async {
      final c = _client(_Adapter());
      await c.dio.get(
        '/x',
        options: Options(headers: {'Authorization': 'Bearer nope'}),
      );
      expect(c.lines.join('\\n'), isNot(contains('Authorization')));
      expect(c.lines.join('\\n'), isNot(contains('nope')));
    });

    test('masks tokens in a response, however deeply nested', () async {
      final c = _client(
        _Adapter(
          status: 201,
          body: {
            'access_token': 'eyJhbGciOi.real.jwt',
            'user': {'display_name': 'Alex', 'refresh_token': 'refresh-secret'},
            'list': [
              {'password': 'hunter2'},
            ],
          },
        ),
      );
      await c.dio.post('/api/v1/auth/dev-login', data: {'password': 'hunter2'});

      final all = c.lines.join('\\n');
      for (final secret in [
        'eyJhbGciOi.real.jwt',
        'refresh-secret',
        'hunter2',
      ]) {
        expect(all, isNot(contains(secret)), reason: '$secret leaked');
      }
      expect(
        all,
        contains('"display_name":"Alex"'),
      ); // ordinary data stays readable
    });

    test('shortens capability links wherever they appear', () async {
      final c = _client(
        _Adapter(
          status: 201,
          body: {
            'invite_url':
                'https://web.test/invite/inv_G0QCaELEdSPcd_9qStnhYWIvvLeRPdwTmB8Yk0NUEAA',
            'note':
                'jury link jry_z1xOONfQwkYlIwgkxeIdQ4ncItGQk-Dn-sygaYZqHFM here',
          },
        ),
      );
      await c.dio.get(
        '/api/v1/invites/inv_G0QCaELEdSPcd_9qStnhYWIvvLeRPdwTmB8Yk0NUEAA',
      );

      final all = c.lines.join('\\n');
      expect(all, contains('inv_G0QC…'));
      expect(all, contains('jry_z1xO…'));
      expect(all, isNot(contains('G0QCaELEdSPcd')));
      expect(all, isNot(contains('z1xOONfQwkYl')));
    });

    test('masks secrets in a query string too', () async {
      final c = _client(_Adapter());
      await c.dio.get(
        '/api/v1/jury/jry_abcdEFGHijklMNOP',
        queryParameters: {'voter': 'juror-key'},
      );
      expect(c.lines.first, contains('jry_abcd…'));
      expect(c.lines.first, isNot(contains('EFGHijkl')));
    });
  });

  group('body handling', () {
    test('truncates a long body and says how much was cut', () async {
      final c = _client(_Adapter(body: {'text': 'x' * 5000}), maxBody: 200);
      await c.dio.get('/x');

      final line = c.lines.last;
      expect(line.length, lessThan(300));
      expect(line, matches(RegExp(r'… \(\+\d+ chars\)$')));
    });

    test('leaves a short body whole', () {
      expect(LogRedactor.body({'a': 1}), '{"a":1}');
      expect(LogRedactor.body(null), '');
    });

    test('does not choke on a body that is not JSON-encodable', () {
      expect(() => LogRedactor.body(Object()), returnsNormally);
    });
  });

  group('LogRedactor', () {
    test('masks any key that looks like a secret, case-insensitively', () {
      final out =
          LogRedactor.value({
                'Authorization': 'Bearer x',
                'API_SECRET': 'y',
                'invite_token': 'z',
                'Cookie': 'c',
                'title': 'visible',
              })
              as Map;
      expect(out['Authorization'], LogRedactor.mask);
      expect(out['API_SECRET'], LogRedactor.mask);
      expect(out['invite_token'], LogRedactor.mask);
      expect(out['Cookie'], LogRedactor.mask);
      expect(out['title'], 'visible');
    });

    test('leaves ordinary text alone', () {
      expect(LogRedactor.text('The Last Pizza Slice'), 'The Last Pizza Slice');
      expect(LogRedactor.text('inv_ is not a link'), 'inv_ is not a link');
    });
  });
}
