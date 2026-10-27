import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'models.dart';

class ApiException implements Exception {
  final int status; // 0 = could not reach the server
  final String message;

  const ApiException(this.status, this.message);

  @override
  String toString() => message;
}

/// Talks to the GeoApp API. Keeps the login tokens in the phone's secure storage and
/// refreshes the access token on its own when it expires.
class ApiClient {
  static const _tokenKey = 'geoapp.tokens';
  static const _timeout = Duration(seconds: 20);
  static const _uploadTimeout = Duration(seconds: 90);

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final http.Client _http = http.Client();

  String? _access;
  String? _refresh;
  Future<bool>? _refreshing;

  bool get hasTokens => _refresh != null;

  String absoluteUrl(String path) => '${Config.apiBase}$path';

  // ---- tokens ----

  Future<void> loadTokens() async {
    try {
      final raw = await _storage.read(key: _tokenKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _access = map['a'] as String?;
      _refresh = map['r'] as String?;
    } catch (_) {
      // Unreadable storage: start signed out.
    }
  }

  Future<void> _saveTokens(String? access, String? refresh) async {
    _access = access;
    _refresh = refresh;
    try {
      if (access == null || refresh == null) {
        await _storage.delete(key: _tokenKey);
      } else {
        await _storage.write(key: _tokenKey, value: jsonEncode({'a': access, 'r': refresh}));
      }
    } catch (_) {
      // The session just will not survive an app restart.
    }
  }

  Map<String, String> _headers({required bool auth, bool json = false}) => {
        if (json) 'Content-Type': 'application/json',
        if (auth && _access != null) 'Authorization': 'Bearer $_access',
      };

  Future<bool> _refreshTokens() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final token = _refresh;
    if (token == null) return false;
    try {
      final res = await _http
          .post(_uri('/api/auth/refresh'), headers: _headers(auth: false, json: true), body: jsonEncode({'refreshToken': token}))
          .timeout(_timeout);
      if (res.statusCode != 200) {
        await _saveTokens(null, null);
        return false;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      await _saveTokens(body['accessToken'] as String, body['refreshToken'] as String);
      return true;
    } catch (_) {
      return false; // network trouble: keep the tokens and try again later
    }
  }

  // ---- plumbing ----

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse('${Config.apiBase}$path').replace(queryParameters: query);

  /// Sends a request, retrying once with a fresh token after a 401.
  Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) call, {
    bool auth = true,
    bool json = false,
    Duration timeout = _timeout,
  }) async {
    try {
      var res = await call(_headers(auth: auth, json: json)).timeout(timeout);
      if (res.statusCode == 401 && auth && _refresh != null && await _refreshTokens()) {
        res = await call(_headers(auth: auth, json: json)).timeout(timeout);
      }
      return res;
    } on TimeoutException {
      throw const ApiException(0, 'The server took too long to answer. Try again.');
    } on http.ClientException {
      throw const ApiException(0, 'Cannot reach the server. Check your connection and that the API is running.');
    }
  }

  dynamic _decode(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      var message = 'Request failed (${res.statusCode})';
      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        if (body['message'] is String) message = body['message'] as String;
      } catch (_) {
        // not JSON
      }
      throw ApiException(res.statusCode, message);
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }

  // ---- auth ----

  Future<Me> login(String email, String password) => _authenticate('/api/auth/login', email, password);

  Future<Me> register(String email, String password) => _authenticate('/api/auth/register', email, password);

  Future<Me> _authenticate(String path, String email, String password) async {
    final res = await _send(
      (h) => _http.post(_uri(path), headers: h, body: jsonEncode({'email': email.trim(), 'password': password})),
      auth: false,
      json: true,
    );
    final body = _decode(res) as Map<String, dynamic>;
    await _saveTokens(body['accessToken'] as String, body['refreshToken'] as String);
    return Me.fromJson(body['user'] as Map<String, dynamic>);
  }

  Future<Me> me() async => Me.fromJson(_decode(await _send((h) => _http.get(_uri('/api/auth/me'), headers: h))) as Map<String, dynamic>);

  Future<void> logout() async {
    final token = _refresh;
    await _saveTokens(null, null);
    if (token == null) return;
    try {
      await _http
          .post(_uri('/api/auth/logout'), headers: _headers(auth: false, json: true), body: jsonEncode({'refreshToken': token}))
          .timeout(_timeout);
    } catch (_) {
      // Already signed out on this phone; the server token expires on its own.
    }
  }

  // ---- posts ----

  /// Approved posts within the default radius of the point. No login needed.
  Future<List<Post>> nearby(double lat, double lng) async {
    final res = await _send(
      (h) => _http.get(_uri('/api/posts/nearby', {'lat': '$lat', 'lng': '$lng'}), headers: h),
      auth: false,
    );
    return (_decode(res) as List<dynamic>).map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Tells the moderators about a post. One report per user per post.
  Future<void> reportPost(String postId, String reason) async {
    final res = await _send(
      (h) => _http.post(_uri('/api/posts/$postId/report'), headers: h, body: jsonEncode({'reason': reason.trim()})),
      json: true,
    );
    _decode(res);
  }

  Future<List<Post>> mine() async {
    final res = await _send((h) => _http.get(_uri('/api/posts/mine'), headers: h));
    return (_decode(res) as List<dynamic>).map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Creates a post from a file (photo, video or audio, with an optional caption) or, with no file, from [text].
  Future<Post> createPost({
    String? filePath,
    String? text,
    required double lat,
    required double lng,
    required double? accuracy,
    String? caption,
  }) async {
    final res = await _send(
      (h) async {
        // A multipart request can only be sent once, so build a new one for every attempt.
        final req = http.MultipartRequest('POST', _uri('/api/posts'))
          ..headers.addAll(h)
          ..fields['lat'] = '$lat'
          ..fields['lng'] = '$lng';
        if (accuracy != null) req.fields['accuracy'] = '$accuracy';
        if (filePath != null) {
          if (caption != null && caption.trim().isNotEmpty) req.fields['caption'] = caption.trim();
          req.files.add(await http.MultipartFile.fromPath('file', filePath));
        } else if (text != null) {
          req.fields['text'] = text.trim();
        }
        return http.Response.fromStream(await _http.send(req));
      },
      timeout: _uploadTimeout,
    );
    return Post.fromJson(_decode(res) as Map<String, dynamic>);
  }
}
