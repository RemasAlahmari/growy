// test/services/api_client_test.dart
//
// Unit tests for the pure helper functions of ApiClient.
// They use fake http.Response objects, so no network or Firebase is needed.
// Test IDs match the Growy outcome table: UT-NFR3-07, UT-NFR3-08, UT-NFR3-09.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:growy/config/api_config.dart';
import 'package:growy/services/api_client.dart';

/// A fake backend response with a FastAPI-style body: {"detail": "..."}.
http.Response withDetail(int status, String detail) =>
    http.Response(jsonEncode({'detail': detail}), status);

void main() {
  // ===== UT-NFR3-07: errorFor turns server errors into safe messages =====
  group('UT-NFR3-07 ApiClient.errorFor', () {
    test('401 gives unauthorized', () {
      final e = ApiClient.errorFor(withDetail(401, 'Invalid or expired token'));
      expect(e.kind, ApiErrorKind.unauthorized);
      expect(e.statusCode, 401);
      expect(e.message, isNotEmpty);
    });

    test('404 uses the server detail', () {
      final e = ApiClient.errorFor(withDetail(404, 'Habit not found'));
      expect(e.kind, ApiErrorKind.notFound);
      expect(e.message, 'Habit not found');
    });

    test('404 without detail gives the default message', () {
      final e = ApiClient.errorFor(http.Response('', 404));
      expect(e.kind, ApiErrorKind.notFound);
      expect(e.message, 'Not found.');
    });

    test('409 gives conflict with the server detail', () {
      final e = ApiClient.errorFor(withDetail(409, 'That username is taken'));
      expect(e.kind, ApiErrorKind.conflict);
      expect(e.message, 'That username is taken');
    });

    test('409 without detail gives the default message', () {
      final e = ApiClient.errorFor(http.Response('', 409));
      expect(e.kind, ApiErrorKind.conflict);
      expect(e.message, 'That already exists.');
    });

    test('503 with detail uses the detail', () {
      final e = ApiClient.errorFor(
          withDetail(503, "The server can't check logins right now."));
      expect(e.kind, ApiErrorKind.server);
      expect(e.message, "The server can't check logins right now.");
    });

    test('503 without detail gives the generic server message', () {
      final e = ApiClient.errorFor(http.Response('', 503));
      expect(e.kind, ApiErrorKind.server);
      expect(e.message, 'The server had a problem (503). Please try again.');
    });

    test('500 gives the generic server message', () {
      final e = ApiClient.errorFor(http.Response('Internal Server Error', 500));
      expect(e.kind, ApiErrorKind.server);
      expect(e.statusCode, 500);
      expect(e.message, 'The server had a problem (500). Please try again.');
    });

    test('non-JSON body gives the default message', () {
      final e = ApiClient.errorFor(http.Response('<html>Bad request</html>', 400));
      expect(e.kind, ApiErrorKind.other);
      expect(e.message, 'Something went wrong (400). Please try again.');
    });

    test('422 validation error (detail is a list) gives the default message', () {
      final body = jsonEncode({
        'detail': [
          {'loc': ['body', 'username'], 'msg': 'too short'}
        ]
      });
      final e = ApiClient.errorFor(http.Response(body, 422));
      expect(e.kind, ApiErrorKind.other);
      expect(e.message, 'Something went wrong (422). Please try again.');
    });
  });

  // ===== UT-NFR3-08: decode reads success answers and throws on errors =====
  group('UT-NFR3-08 ApiClient.decode', () {
    test('200 with an empty body returns null', () {
      expect(ApiClient.decode(http.Response('', 200)), isNull);
    });

    test('200 with JSON returns a map', () {
      final body = ApiClient.decode(
          http.Response('{"username": "sara", "total_points": 10}', 200));
      expect(body, isA<Map<String, dynamic>>());
      expect(body['username'], 'sara');
      expect(body['total_points'], 10);
    });

    test('400 throws an ApiException', () {
      expect(
            () => ApiClient.decode(withDetail(400, 'Bad request')),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', 'Bad request')),
      );
    });
  });

  // ===== UT-NFR3-09: absoluteUrl adds the backend address to paths only =====
  group('UT-NFR3-09 ApiClient.absoluteUrl', () {
    test('null stays null', () {
      expect(ApiClient.absoluteUrl(null), isNull);
    });

    test('empty string stays empty', () {
      expect(ApiClient.absoluteUrl(''), '');
    });

    test('a path gets the backend address in front', () {
      expect(ApiClient.absoluteUrl('/photos/a.jpg'),
          '${ApiConfig.baseUrl}/photos/a.jpg');
    });

    test('a full https URL is unchanged', () {
      const url = 'https://example.com/photos/a.jpg';
      expect(ApiClient.absoluteUrl(url), url);
    });
  });
}