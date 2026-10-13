import 'package:dio/dio.dart';

import 'api_log.dart';
import 'env.dart';
import 'models.dart';

/// Thrown for anything the API rejected. Carries the server's own message so
/// the UI can show what actually went wrong rather than a generic apology.
class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message, {this.fields});

  final int statusCode;
  final String code;
  final String message;
  final Map<String, String>? fields;

  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isRateLimited => statusCode == 429;
  bool get isNetwork => statusCode == 0;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required String baseUrl, Dio? dio})
    : _dio = dio ?? _buildDio(baseUrl);

  static Dio _buildDio(String baseUrl) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        contentType: 'application/json',
        // We map status codes ourselves so every failure becomes an
        // ApiException with the server's message intact.
        validateStatus: (_) => true,
      ),
    );
    if (Env.apiLog) dio.interceptors.add(ApiLogInterceptor());
    return dio;
  }

  final Dio _dio;
  String? _token;

  // ignore: avoid_setters_without_getters
  set token(String? value) => _token = value;

  Options get _options => Options(
    headers: _token == null ? null : {'Authorization': 'Bearer $_token'},
  );

  Future<T> _send<T>(
    Future<Response<dynamic>> Function() call,
    T Function(dynamic data) parse,
  ) async {
    late final Response<dynamic> response;
    try {
      response = await call();
    } on DioException catch (error) {
      throw ApiException(
        0,
        'network_error',
        error.type == DioExceptionType.connectionTimeout ||
                error.type == DioExceptionType.receiveTimeout
            ? 'The courthouse is slow to answer. Try again.'
            : 'Could not reach the courthouse. Check your connection.',
      );
    }

    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return parse(response.data);

    final body = response.data;
    final data = body is Map<String, dynamic>
        ? body
        : const <String, dynamic>{};
    throw ApiException(
      status,
      data['error'] as String? ?? 'http_error',
      data['message'] as String? ?? 'Something went wrong.',
      fields: _fieldErrors(data),
    );
  }

  Map<String, String>? _fieldErrors(Map<String, dynamic> data) {
    final raw = data['fields'];
    if (raw is! List) return null;
    return {
      for (final entry in raw)
        if (entry is Map && entry['field'] is String)
          entry['field'] as String: entry['message'] as String? ?? 'Invalid',
    };
  }

  // --- auth ---------------------------------------------------------------

  Future<Session> devLogin(String subject, String displayName) => _send(
    () => _dio.post(
      '/api/v1/auth/dev-login',
      data: {'auth_subject': subject, 'display_name': displayName},
    ),
    (data) => Session.fromJson(data as Map<String, dynamic>),
  );

  Future<Session> register(String email, String password, String displayName) =>
      _send(
        () => _dio.post(
          '/api/v1/auth/register',
          data: {
            'email': email,
            'password': password,
            'display_name': displayName,
          },
        ),
        (data) => Session.fromJson(data as Map<String, dynamic>),
      );

  Future<Session> login(String email, String password) => _send(
    () => _dio.post(
      '/api/v1/auth/login',
      data: {'email': email, 'password': password},
    ),
    (data) => Session.fromJson(data as Map<String, dynamic>),
  );

  // --- cases --------------------------------------------------------------

  Future<List<CaseSummary>> listCases() => _send(
    () => _dio.get('/api/v1/cases', options: _options),
    (data) => (data as List<dynamic>)
        .map((e) => CaseSummary.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  Future<CaseDetail> createCase({
    required String title,
    required String category,
    required String accusation,
    String? defendantNickname,
    String? courtId,
    String? accusedUserId,
  }) => _send(
    () => _dio.post(
      '/api/v1/cases',
      options: _options,
      data: {
        'title': title,
        'category': category,
        'accusation': accusation,
        if (defendantNickname != null && defendantNickname.isNotEmpty)
          'defendant_nickname': defendantNickname,
        if (courtId != null) 'court_id': courtId,
        if (accusedUserId != null) 'accused_user_id': accusedUserId,
      },
    ),
    (data) => CaseDetail.fromJson(data as Map<String, dynamic>),
  );

  Future<CaseDetail> getCase(String id) => _send(
    () => _dio.get('/api/v1/cases/$id', options: _options),
    (data) => CaseDetail.fromJson(data as Map<String, dynamic>),
  );

  Future<void> deleteCase(String id) =>
      _send(() => _dio.delete('/api/v1/cases/$id', options: _options), (_) {});

  /// This court's standings: who keeps getting convicted.
  Future<List<RapSheetEntry>> rapSheet() => _send(
    () => _dio.get('/api/v1/cases/rap-sheet', options: _options),
    (data) => (data as List<dynamic>)
        .map((e) => RapSheetEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  // --- verdicts -----------------------------------------------------------

  Future<VerdictState> requestVerdict(String id) => _send(
    () => _dio.post('/api/v1/cases/$id/verdict', options: _options),
    (data) => VerdictState.fromJson(data as Map<String, dynamic>),
  );

  Future<VerdictState> getVerdict(String id) => _send(
    () => _dio.get('/api/v1/cases/$id/verdict', options: _options),
    (data) => VerdictState.fromJson(data as Map<String, dynamic>),
  );

  // --- sharing ------------------------------------------------------------

  Future<ShareLink> enableShare(String id) => _send(
    () => _dio.post('/api/v1/cases/$id/share', options: _options),
    (data) => ShareLink.fromJson(data as Map<String, dynamic>),
  );

  Future<void> revokeShare(String id) => _send(
    () => _dio.delete('/api/v1/cases/$id/share', options: _options),
    (_) {},
  );

  // --- users, courts, shared cases, notifications --------------------------

  Future<List<UserRef>> searchUsers(String query) => _send(
    () => _dio.get(
      '/api/v1/users/search',
      queryParameters: {'q': query},
      options: _options,
    ),
    (data) => (data as List<dynamic>)
        .map((e) => UserRef.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  Future<List<Court>> listCourts() => _send(
    () => _dio.get('/api/v1/courts', options: _options),
    (data) => (data as List<dynamic>)
        .map((e) => Court.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  Future<Court> createCourt(String name) => _send(
    () => _dio.post('/api/v1/courts', data: {'name': name}, options: _options),
    (data) => Court.fromJson(data as Map<String, dynamic>),
  );

  Future<Court> addCourtMember(String courtId, String userId) => _send(
    () => _dio.post(
      '/api/v1/courts/$courtId/members',
      data: {'user_id': userId},
      options: _options,
    ),
    (data) => Court.fromJson(data as Map<String, dynamic>),
  );

  Future<Court> joinCourt(String inviteCode) => _send(
    () => _dio.post(
      '/api/v1/courts/join',
      data: {'invite_code': inviteCode},
      options: _options,
    ),
    (data) => Court.fromJson(data as Map<String, dynamic>),
  );

  Future<void> removeCourtMember(String courtId, String userId) => _send(
    () => _dio.delete(
      '/api/v1/courts/$courtId/members/$userId',
      options: _options,
    ),
    (_) {},
  );

  Future<void> addCaseMember(String caseId, String userId, String role) =>
      _send(
        () => _dio.post(
          '/api/v1/cases/$caseId/members',
          data: {'user_id': userId, 'role': role},
          options: _options,
        ),
        (_) {},
      );

  Future<List<SharedCase>> sharedCases() => _send(
    () => _dio.get('/api/v1/cases/shared', options: _options),
    (data) => (data as List<dynamic>)
        .map((e) => SharedCase.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  // --- the jury box -------------------------------------------------------
  //
  // Unauthenticated on the server: the jury link *is* the capability. The
  // signed-in user id is the voter key, so one account is one vote however
  // many times they open the summons.

  Future<JuryRoom> juryRoom(String token, {required String voterKey}) => _send(
    () => _dio.get(
      '/api/v1/jury/$token',
      queryParameters: {'voter': voterKey},
      options: _options,
    ),
    (data) => JuryRoom.fromJson(data as Map<String, dynamic>),
  );

  Future<JuryTally> castVote(
    String token, {
    required String vote,
    required String voterKey,
    String? jurorName,
  }) => _send(
    () => _dio.post(
      '/api/v1/jury/$token/vote',
      data: {
        'voter_key': voterKey,
        'vote': vote,
        if (jurorName != null && jurorName.isNotEmpty) 'juror_name': jurorName,
      },
      options: _options,
    ),
    (data) => JuryTally.fromJson(
      (data as Map<String, dynamic>)['tally'] as Map<String, dynamic>,
    ),
  );

  Future<NotificationFeed> notifications() => _send(
    () => _dio.get('/api/v1/notifications', options: _options),
    (data) => NotificationFeed.fromJson(data as Map<String, dynamic>),
  );

  Future<void> markNotificationsRead() => _send(
    () => _dio.post('/api/v1/notifications/read-all', options: _options),
    (_) {},
  );

  /// Tells the server where to push notifications for this device.
  Future<void> registerDevice(String token, {String platform = 'android'}) =>
      _send(
        () => _dio.post(
          '/api/v1/devices',
          data: {'token': token, 'platform': platform},
          options: _options,
        ),
        (_) {},
      );
}
