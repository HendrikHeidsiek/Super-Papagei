import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  final int? status;
  final String message;
  ApiException(this.message, [this.status]);
  bool get unauthorized => status == 401;
  @override
  String toString() => message;
}

class Api {
  final String baseUrl;
  final String? token;
  final http.Client _client;
  Api(String baseUrl, this.token, [http.Client? client])
      : baseUrl = normalize(baseUrl),
        _client = client ?? http.Client();

  static String normalize(String url) {
    var u = url.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Map<String, String> get authHeaders => token == null ? {} : {'Authorization': 'Bearer $token'};

  Uri _u(String path, [Map<String, String>? q]) => Uri.parse('$baseUrl$path').replace(queryParameters: q);

  String coverUrl(String bookId, {bool full = false}) =>
      '$baseUrl/api/books/$bookId/cover?size=${full ? 'full' : 'thumb'}';

  /// Token goes into the query string as well: some native players drop headers on redirects.
  String fileUrl(String bookId, AudioFileInfo f) => '$baseUrl/api/books/$bookId/files/${f.index}.${f.ext}?token=$token';

  Future<dynamic> _send(String method, String path,
      {Object? body, Map<String, String>? query, Duration timeout = const Duration(seconds: 20)}) async {
    final req = http.Request(method, _u(path, query));
    req.headers.addAll(authHeaders);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    late http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(timeout));
    } on TimeoutException {
      throw ApiException('Server antwortet nicht');
    } catch (e) {
      throw ApiException('Server nicht erreichbar');
    }
    if (res.statusCode >= 400) {
      String msg = 'Fehler ${res.statusCode}';
      try {
        final d = jsonDecode(utf8.decode(res.bodyBytes));
        if (d is Map && d['detail'] is String) msg = d['detail'];
      } catch (_) {}
      throw ApiException(msg, res.statusCode);
    }
    if (res.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<Map<String, dynamic>> health() async =>
      (await _send('GET', '/api/health', timeout: const Duration(seconds: 8))) as Map<String, dynamic>;

  Future<(String, UserInfo)> login(String username, String password, String device) async {
    final d = await _send('POST', '/api/auth/login',
        body: {'username': username, 'password': password, 'device': device}) as Map<String, dynamic>;
    return (d['token'] as String, UserInfo.fromJson(d['user']));
  }

  Future<void> logout() async => _send('POST', '/api/auth/logout');

  Future<UserInfo> me() async => UserInfo.fromJson(await _send('GET', '/api/me'));

  Future<void> changePassword(String oldPw, String newPw) async =>
      _send('PUT', '/api/me/password', body: {'old_password': oldPw, 'new_password': newPw});

  /// Returns null when the server says the library is unchanged (ETag match).
  Future<(String etag, String body)?> library(String? etag) async {
    final req = http.Request('GET', _u('/api/library'));
    req.headers.addAll(authHeaders);
    if (etag != null) req.headers['If-None-Match'] = etag;
    http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(const Duration(seconds: 40)));
    } catch (_) {
      throw ApiException('Server nicht erreichbar');
    }
    if (res.statusCode == 304) return null;
    if (res.statusCode >= 400) throw ApiException('Fehler ${res.statusCode}', res.statusCode);
    return (res.headers['etag'] ?? '', utf8.decode(res.bodyBytes));
  }

  Future<List<Progress>> progress() async =>
      ((await _send('GET', '/api/progress')) as List).map((e) => Progress.fromJson(e)).toList();

  Future<List<Progress>> pushProgress(List<Progress> items) async =>
      ((await _send('PUT', '/api/progress', body: {'items': items.map((e) => e.toJson()).toList()})) as List)
          .map((e) => Progress.fromJson(e))
          .toList();

  Future<void> resetProgress(String bookId) async => _send('DELETE', '/api/progress/$bookId');

  Future<List<Map<String, dynamic>>> progressHistory(String bookId) async =>
      ((await _send('GET', '/api/progress/$bookId/history')) as List).cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> bookmarks(String bookId) async =>
      ((await _send('GET', '/api/books/$bookId/bookmarks')) as List).cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> addBookmark(String bookId, double position, String? note) async =>
      (await _send('POST', '/api/books/$bookId/bookmarks', body: {'position': position, 'note': note}))
          as Map<String, dynamic>;

  Future<void> deleteBookmark(int id) async => _send('DELETE', '/api/bookmarks/$id');

  String avatarUrl(int userId) => '$baseUrl/api/users/$userId/avatar';

  Future<UserInfo> uploadAvatar(List<int> bytes) async {
    final req = http.Request('PUT', _u('/api/me/avatar'));
    req.headers.addAll(authHeaders);
    req.headers['Content-Type'] = 'application/octet-stream';
    req.bodyBytes = bytes;
    http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(const Duration(seconds: 60)));
    } catch (_) {
      throw ApiException('Server nicht erreichbar');
    }
    if (res.statusCode >= 400) {
      String msg = 'Fehler ${res.statusCode}';
      try {
        final d = jsonDecode(utf8.decode(res.bodyBytes));
        if (d is Map && d['detail'] is String) msg = d['detail'];
      } catch (_) {}
      throw ApiException(msg, res.statusCode);
    }
    return UserInfo.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  Future<UserInfo> deleteAvatar() async => UserInfo.fromJson(await _send('DELETE', '/api/me/avatar'));

  Future<List<UserInfo>> users() async =>
      ((await _send('GET', '/api/users')) as List).map((e) => UserInfo.fromJson(e)).toList();

  Future<void> createUser(String username, String displayName, String password, bool admin) async =>
      _send('POST', '/api/users',
          body: {'username': username, 'display_name': displayName, 'password': password, 'is_admin': admin});

  Future<void> deleteUser(int id) async => _send('DELETE', '/api/users/$id');

  Future<void> resetUserPassword(int id, String pw) async =>
      _send('PUT', '/api/users/$id/password', body: {'new_password': pw});

  Future<Map<String, dynamic>> scan({bool force = false}) async =>
      (await _send('POST', '/api/library/scan', query: {'force': '$force'})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> scanState() async =>
      (await _send('GET', '/api/library/scan')) as Map<String, dynamic>;
}
