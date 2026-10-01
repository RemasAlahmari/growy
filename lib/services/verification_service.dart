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
    this.pointsEarned = 0,
  });
 
  final String status; // "verified" or "rejected"
  final String? predictedLabel; // the CLIP label that won
  final double? confidence; // 0.0 – 1.0
  final int pointsEarned;
 
  bool get isVerified => status == 'verified';
 
  factory VerificationResult.fromJson(Map<String, dynamic> json) {
    return VerificationResult(
      status: json['verification_status'] as String? ?? 'rejected',
      predictedLabel: json['predicted_label'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
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
  // CLIP can take a few seconds, especially on the first request after startup.
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
    throw VerificationException(
      'Something went wrong (${response.statusCode}). Please try again.',
    );
  }
}