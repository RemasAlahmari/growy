// UT-FR3.4-01: VerificationResult.fromJson reads what
// POST /habits/{id}/complete/ai returns, and fills in safe defaults.
import 'package:flutter_test/flutter_test.dart';
import 'package:growy/services/verification_service.dart';

void main() {
  group('VerificationResult.fromJson', () {
    test('full verified response: every field is read', () {
      final r = VerificationResult.fromJson({
        'verification_status': 'verified',
        'predicted_label': 'walking',
        'confidence': 0.92,
        'confidence_level': 'high',
        'reason': 'Feet walking on a sidewalk.',
        'points_earned': 10,
        'total_points': 105,
        'current_level': 1,
        'leveled_up': true,
        'attempts_remaining': 3,
      });

      expect(r.status, 'verified');
      expect(r.isVerified, isTrue);
      expect(r.predictedLabel, 'walking');
      expect(r.confidence, 0.92);
      expect(r.confidenceLevel, 'high');
      expect(r.reason, 'Feet walking on a sidewalk.');
      expect(r.pointsEarned, 10);
      expect(r.totalPoints, 105);
      expect(r.currentLevel, 1);
      expect(r.leveledUp, isTrue);
      expect(r.attemptsRemaining, 3);
    });

    test('missing status is treated as rejected', () {
      final r = VerificationResult.fromJson({'reason': 'No status sent.'});

      expect(r.status, 'rejected');
      expect(r.isVerified, isFalse);
      expect(r.pointsEarned, 0); // missing points -> 0
    });

    test('null confidence (Gemini sends a level instead) stays null', () {
      final r = VerificationResult.fromJson({
        'verification_status': 'rejected',
        'confidence': null,
        'confidence_level': 'low',
        'attempts_remaining': 2,
      });

      expect(r.confidence, isNull);
      expect(r.confidenceLevel, 'low');
      expect(r.attemptsRemaining, 2);
    });

    test('whole numbers are accepted for confidence (JSON may send 1 not 1.0)', () {
      final r = VerificationResult.fromJson({
        'verification_status': 'verified',
        'confidence': 1,
      });

      expect(r.confidence, 1.0);
    });

    test('missing leveled_up defaults to false', () {
      final r = VerificationResult.fromJson({
        'verification_status': 'verified',
        'points_earned': 5,
        'total_points': 20,
        'current_level': 0,
      });

      expect(r.leveledUp, isFalse);
      expect(r.pointsEarned, 5);
      expect(r.totalPoints, 20);
      expect(r.currentLevel, 0);
    });

    test('missing optional fields are null, not an error', () {
      final r = VerificationResult.fromJson({'verification_status': 'verified'});

      expect(r.predictedLabel, isNull);
      expect(r.reason, isNull);
      expect(r.totalPoints, isNull);
      expect(r.currentLevel, isNull);
      expect(r.attemptsRemaining, isNull);
    });
  });
}