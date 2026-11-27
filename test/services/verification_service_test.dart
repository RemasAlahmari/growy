// UT-FR3.4-02: VerificationService with a fake server (MockClient).
// Each server answer gives the right result or the right message for the user.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:growy/services/verification_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

/// A small fake photo. On phones/desktop XFile takes its name from the path.
XFile fakePhoto([String name = 'photo.jpg']) => XFile.fromData(
      Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]),
      name: name,
      path: name,
    );

/// A service whose server always answers [status] with [body].
VerificationService serviceAnswering(int status, [String body = '{}']) {
  return VerificationService(
    client: MockClient((request) async => http.Response(body, status)),
    getToken: () async => 'test-token',
  );
}

/// Expects submitPhoto to fail with a message containing [text].
Future<void> expectMessage(
  VerificationService service,
  String text, {
  bool outOfAttempts = false,
}) async {
  await expectLater(
    service.submitPhoto(habitId: '1', photo: fakePhoto()),
    throwsA(
      isA<VerificationException>()
          .having((e) => e.message, 'message', contains(text))
          .having((e) => e.outOfAttempts, 'outOfAttempts', outOfAttempts),
    ),
  );
}

void main() {
  group('VerificationService.submitPhoto', () {
    test('200: returns the parsed result and sends a correct request', () async {
      late http.Request sent;
      final service = VerificationService(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'verification_status': 'verified',
              'predicted_label': 'walking',
              'confidence_level': 'high',
              'reason': 'Feet walking on a sidewalk.',
              'points_earned': 10,
              'total_points': 10,
              'current_level': 0,
              'leveled_up': false,
            }),
            200,
          );
        }),
        getToken: () async => 'test-token',
      );

      final result = await service.submitPhoto(habitId: '7', photo: fakePhoto());

      expect(result.isVerified, isTrue);
      expect(result.predictedLabel, 'walking');
      expect(result.pointsEarned, 10);

      // The request the app sent
      expect(sent.method, 'POST');
      expect(sent.url.path, endsWith('/habits/7/complete/ai'));
      expect(sent.headers['Authorization'], 'Bearer test-token');
      final body = latin1.decode(sent.bodyBytes);
      expect(body, contains('name="file"'));
      expect(body, contains('filename="photo.jpg"'));
      expect(body, contains('content-type: image/jpeg'));
    });

    test('a .png photo is sent as image/png', () async {
      late http.Request sent;
      final service = VerificationService(
        client: MockClient((request) async {
          sent = request;
          return http.Response('{"verification_status": "verified"}', 200);
        }),
        getToken: () async => 'test-token',
      );

      await service.submitPhoto(habitId: '1', photo: fakePhoto('photo.png'));

      expect(latin1.decode(sent.bodyBytes), contains('content-type: image/png'));
    });

    test('409: already completed today', () async {
      await expectMessage(serviceAnswering(409), 'already completed this habit today');
    });

    test('413: photo too large', () async {
      await expectMessage(serviceAnswering(413), 'JPG or PNG photo under 5 MB');
    });

    test('415: wrong file type', () async {
      await expectMessage(serviceAnswering(415), 'JPG or PNG photo under 5 MB');
    });

    test('429: out of attempts (and flagged as such)', () async {
      await expectMessage(serviceAnswering(429), 'used all your attempts',
          outOfAttempts: true);
    });

    test('503: AI busy', () async {
      await expectMessage(serviceAnswering(503), 'Photo checking is busy');
    });

    test('401: session expired', () async {
      await expectMessage(serviceAnswering(401), 'session expired');
    });

    test('other status (500): general message with the code', () async {
      await expectMessage(serviceAnswering(500), 'Something went wrong (500)');
    });

    test('network error: could not reach the server', () async {
      final service = VerificationService(
        client: MockClient((_) async => throw http.ClientException('No internet')),
        getToken: () async => 'test-token',
      );
      await expectMessage(service, 'Could not reach the server');
    });

    test('not logged in: nothing is sent', () async {
      var requests = 0;
      final service = VerificationService(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
        getToken: () async => null,
      );

      await expectMessage(service, 'not logged in');
      expect(requests, 0);
    });
  });
}
