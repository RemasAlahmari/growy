import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/api_config.dart';

/// What went wrong with a backend request.
enum ApiErrorKind { network, unauthorized, notFound, conflict, server, other }

/// A backend error with a message that is safe to show to the user.
class ApiException implements Exception {
  ApiException(this.kind, this.message, {this.statusCode});

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException(${statusCode ?? kind.name}): $message';
}

/// Shared code for calling the Growy backend: the Firebase token header,
/// timeouts, readable errors, and creating a missing user row.
class ApiClient {
  ApiClient._();

  static const Duration timeout = Duration(seconds: 15);

  /// `Authorization: Bearer <Firebase ID token>`, like every endpoint expects.
  static Future<Map<String, String>> authHeaders({bool json = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw ApiException(ApiErrorKind.unauthorized, 'Please log in again.');
    }
    final token = await user.getIdToken();
    return {
      'Authorization': 'Bearer $token',
      if (json) 'Content-Type': 'application/json',
    };
  }

  static Uri uri(String path, [Map<String, String>? query]) {
    final url = Uri.parse('${ApiConfig.baseUrl}$path');
    return (query == null || query.isEmpty)
        ? url
        : url.replace(queryParameters: query);
  }

  static Future<dynamic> getJson(String path, {Map<String, String>? query}) {
    return _send(
      () async => http.get(uri(path, query), headers: await authHeaders()),
    );
  }

  static Future<dynamic> putJson(String path, Map<String, dynamic> body) {
    return _send(
      () async => http.put(
        uri(path),
        headers: await authHeaders(json: true),
        body: jsonEncode(body),
      ),
    );
  }

  static Future<dynamic> postJson(String path, [Map<String, dynamic>? body]) {
    return _send(
      () async => http.post(
        uri(path),
        headers: await authHeaders(json: body != null),
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  static Future<dynamic> deleteJson(String path) {
    return _send(
      () async => http.delete(uri(path), headers: await authHeaders()),
    );
  }

  /// Uploads one image as multipart form-data (field name "file").
  static Future<dynamic> uploadImage(
    String path,
    List<int> bytes, {
    required String filename,
  }) {
    final isPng = filename.toLowerCase().endsWith('.png');
    return _send(() async {
      final request = http.MultipartRequest('POST', uri(path))
        ..headers.addAll(await authHeaders())
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: filename,
            contentType: MediaType('image', isPng ? 'png' : 'jpeg'),
          ),
        );
      return http.Response.fromStream(await request.send());
    });
  }

  /// The backend sends photo addresses as paths ("/photos/abc.jpg");
  /// this adds the backend address in front. Full URLs are returned as is.
  static String? absoluteUrl(String? pathOrUrl) {
    if (pathOrUrl == null || pathOrUrl.isEmpty) return pathOrUrl;
    if (pathOrUrl.startsWith('/')) return '${ApiConfig.baseUrl}$pathOrUrl';
    return pathOrUrl;
  }

  /// POST /users/sync: makes sure the logged-in Firebase user has a row in
  /// the database. Safe to call any number of times. Sign Up passes the
  /// username and gender; Login calls it without them.
  static Future<Map<String, dynamic>> syncUser({
    String? username,
    String? gender,
  }) async {
    final query = <String, String>{
      if (username != null && username.isNotEmpty) 'username': username,
      if (gender != null && gender.isNotEmpty) 'gender': gender,
    };
    final response = await _run(
      () async =>
          http.post(uri('/users/sync', query), headers: await authHeaders()),
    );
    return decode(response) as Map<String, dynamic>;
  }

  /// Sends the request. If the backend answers "User not found" (the account
  /// exists in Firebase but has no row in our database yet), creates the row
  /// with POST /users/sync and tries once more.
  static Future<dynamic> _send(Future<http.Response> Function() request) async {
    var response = await _run(request);
    if (_isMissingUser(response)) {
      debugPrint('User row missing on the backend, calling /users/sync');
      await syncUser();
      response = await _run(request);
    }
    return decode(response);
  }

  static Future<http.Response> _run(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request().timeout(timeout);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      debugPrint('Backend timeout: ${ApiConfig.baseUrl}');
      throw ApiException(
        ApiErrorKind.network,
        kDebugMode
            ? "The server at ${ApiConfig.baseUrl} didn't answer. Is the backend running?"
            : "The server didn't answer. Please try again.",
      );
    } catch (e) {
      // SocketException, ClientException, "Insecure HTTP is not allowed"...
      debugPrint('Backend unreachable (${ApiConfig.baseUrl}): $e');
      throw ApiException(
        ApiErrorKind.network,
        kDebugMode
            ? "Can't reach the server at ${ApiConfig.baseUrl}. "
                  'Is the backend running?'
            : "Can't reach the server. Check your connection and try again.",
      );
    }
  }

  static bool _isMissingUser(http.Response r) =>
      r.statusCode == 404 && r.body.contains('User not found');

  /// The decoded JSON body, or an [ApiException] for an error status.
  static dynamic decode(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return r.body.isEmpty ? null : jsonDecode(r.body);
    }
    debugPrint('Backend error ${r.statusCode} ${r.request?.url}: ${r.body}');
    throw errorFor(r);
  }

  static ApiException errorFor(http.Response r) {
    final detail = _detail(r);
    final code = r.statusCode;
    if (code == 401) {
      return ApiException(
        ApiErrorKind.unauthorized,
        kDebugMode
            ? 'The server rejected your login (401). Log in again; if it keeps '
                  'happening, check that FIREBASE_PROJECT_ID in backend/.env '
                  'matches the app (growy-4036d).'
            : 'Your session expired. Please log in again.',
        statusCode: code,
      );
    }
    if (code == 404) {
      return ApiException(
        ApiErrorKind.notFound,
        detail ?? 'Not found.',
        statusCode: code,
      );
    }
    if (code == 409) {
      return ApiException(
        ApiErrorKind.conflict,
        detail ?? 'That already exists.',
        statusCode: code,
      );
    }
    if (code == 503 && detail != null) {
      // e.g. "The server can't check logins right now..." or the AI is busy.
      return ApiException(ApiErrorKind.server, detail, statusCode: code);
    }
    if (code >= 500) {
      return ApiException(
        ApiErrorKind.server,
        'The server had a problem ($code). Please try again.',
        statusCode: code,
      );
    }
    return ApiException(
      ApiErrorKind.other,
      detail ?? 'Something went wrong ($code). Please try again.',
      statusCode: code,
    );
  }

  /// FastAPI puts a readable message in {"detail": "..."}.
  static String? _detail(http.Response r) {
    try {
      final json = jsonDecode(r.body);
      if (json is Map && json['detail'] is String) return json['detail'] as String;
    } catch (_) {}
    return null;
  }
}
