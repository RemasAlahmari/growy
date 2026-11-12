import 'package:flutter/foundation.dart';

/// Where the Growy backend (FastAPI) runs. Every service builds its URLs from
/// [ApiConfig.baseUrl], so the address is changed in one place.
///
/// Defaults (backend started with `uvicorn main:app --host 0.0.0.0 --port 8000`):
///   - Android emulator → http://10.0.2.2:8000  (10.0.2.2 is the emulator's name for your PC)
///   - Flutter Web, Windows/macOS/Linux desktop, iOS simulator → http://127.0.0.1:8000
///
/// A real phone can't use either of those: "127.0.0.1" on a phone means the phone
/// itself. Pass your PC's Wi-Fi address (or the deployed backend) when running:
///
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
///   flutter run --dart-define=API_BASE_URL=https://growy-api.up.railway.app
class ApiConfig {
  ApiConfig._();

  static const String _fromBuild = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_fromBuild.isNotEmpty) {
      // Allow "http://host:8000/" with a trailing slash.
      return _fromBuild.endsWith('/')
          ? _fromBuild.substring(0, _fromBuild.length - 1)
          : _fromBuild;
    }
    if (kIsWeb) return 'http://127.0.0.1:8000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }
}
