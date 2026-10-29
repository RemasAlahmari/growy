import 'dart:convert';
 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
 
import 'auth_service.dart';
 
/// What POST /habits/{id}/complete/ai returns.
class VerificationResult {
  const VerificationResult({
    required this.status,
    this.predictedLabel,
    this.confidence,
    this.confidenceLevel,
    this.reason,
    this.pointsEarned = 0,
  });

  final String status; // "verified" or "rejected"
  final String? predictedLabel; // the activity the AI detected, e.g. "walking"
  final double? confidence; // 0.0 – 1.0 (null with Gemini, which gives a level instead)
  final String? confidenceLevel; // "high", "medium" or "low"
  final String? reason; // one sentence from the AI explaining its decision
  final int pointsEarned;

  bool get isVerified => status == 'verified';

  factory VerificationResult.fromJson(Map<String, dynamic> json) {
    return VerificationResult(
      status: json['verification_status'] as String? ?? 'rejected',
      predictedLabel: json['predicted_label'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      confidenceLevel: json['confidence_level'] as String?,
      reason: json['reason'] as String?,
      pointsEarned: (json['points_earned'] as num? ?? 0).toInt(),
    );
  }
}

/// An error with a message that is safe to show to the user.
class VerificationException implements Exception {
  VerificationException(this.message);
  final String message;
 
  @override
  String toString() => message;
}
 
class VerificationService {
  // The AI usually answers in a few seconds; the backend gives up after 30 s.
  static const Duration _timeout = Duration(seconds: 60);
 
  /// Uploads the photo as multipart form-data, field name "file".
  Future<VerificationResult> submitPhoto({
    required String habitId,
    required XFile photo,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw VerificationException('You are not logged in.');
    }
    final token = await user.getIdToken();
 
    final uri = Uri.parse(
      '${AuthService.backendUrl}/habits/$habitId/complete/ai',
    );
    final bytes = await photo.readAsBytes();
    final isPng = photo.name.toLowerCase().endsWith('.png');
 
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: photo.name,
          contentType: MediaType('image', isPng ? 'png' : 'jpeg'),
        ),
      );
 
    final http.Response response;
    try {
      final streamed = await request.send().timeout(_timeout);
      response = await http.Response.fromStream(streamed);
    } catch (e) {
      throw VerificationException(
        'Could not reach the server. Check your connection and try again.',
      );
    }
 
    if (response.statusCode == 200) {
      return VerificationResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    if (response.statusCode == 409) {
      throw VerificationException('You already completed this habit today.');
    }
    if (response.statusCode == 413 || response.statusCode == 415) {
      throw VerificationException('Please use a JPG or PNG photo under 5 MB.');
    }
    if (response.statusCode == 503) {
      throw VerificationException(
        'Photo checking is busy right now. Please try again in a minute.',
      );
    }
    if (response.statusCode == 401) {
      throw VerificationException('Your session expired. Please log in again.');
    }
    throw VerificationException(
      'Something went wrong (${response.statusCode}). Please try again.',
    );
  }
}