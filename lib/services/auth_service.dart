import 'package:flutter/foundation.dart' show debugPrint;
import 'package:firebase_auth/firebase_auth.dart';

import '../config/api_config.dart';
import 'api_client.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Kept for older code: the address now lives in [ApiConfig.baseUrl].
  static String get backendUrl => ApiConfig.baseUrl;

  Future<String?> signUp({
    required String email,
    required String password,
    required String username,
    required String gender, // 'male' or 'female'
  }) async {
    try {
      try {
        await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        // The Firebase account may already exist from an earlier Sign Up whose
        // backend step failed (e.g. the server was off). If the password matches,
        // log in and finish creating the Growy account instead of getting stuck.
        if (e.code != 'email-already-in-use') rethrow;
        try {
          await _auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
        } on FirebaseAuthException {
          throw e; // different password: show "email already in use"
        }
      }

      await ApiClient.syncUser(username: username, gender: gender);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Sign up failed';
    } on ApiException catch (e) {
      // The Firebase account exists; pressing Sign Up again (same email and
      // password) or logging in later will finish the setup.
      return 'Your account was created, but the Growy server could not be '
          'reached: ${e.message}';
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> logIn({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Login failed';
    } catch (e) {
      return e.toString();
    }

    // Make sure this account has a row in the Growy database, so Home can load.
    // Not blocking: if the server is down, Home shows the error and a retry button.
    try {
      await ApiClient.syncUser();
    } catch (e) {
      debugPrint('Could not sync user after login: $e');
    }
    return null;
  }

  /// Forgot password: Firebase emails a link where the user sets a new password.
  /// Returns null when the email was sent, otherwise a message to show.
  /// "No account for this email" also returns null, so the app never reveals
  /// which emails have an account.
  Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          return null;
        case 'invalid-email':
          return 'Please enter a valid email address.';
        case 'network-request-failed':
          return 'No internet connection. Please try again.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait a few minutes and try again.';
        default:
          return e.message ?? 'Could not send the reset email. Please try again.';
      }
    } catch (e) {
      debugPrint('Password reset failed: $e');
      return 'Could not send the reset email. Please try again.';
    }
  }
}
