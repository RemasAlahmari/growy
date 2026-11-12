import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await themeController.load();
  runApp(const GrowyApp());
}

class GrowyApp extends StatefulWidget {
  const GrowyApp({super.key});

  @override
  State<GrowyApp> createState() => _GrowyAppState();
}

class _GrowyAppState extends State<GrowyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    themeController.addListener(_applyTheme);
    GrowyPalette.isDark = _shouldBeDark();
  }

  @override
  void dispose() {
    themeController.removeListener(_applyTheme);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Called when the phone switches between light and dark (System mode).
  @override
  void didChangePlatformBrightness() => _applyTheme();

  bool _shouldBeDark() {
    switch (themeController.value) {
      case ThemeMode.dark:
        return true;
      case ThemeMode.light:
        return false;
      case ThemeMode.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    }
  }

  /// Flips the palette, then asks every screen (including ones further back
  /// in the navigation stack) to rebuild with the new colours. Screen state,
  /// like typed text or scroll position, is kept.
  void _applyTheme() {
    final dark = _shouldBeDark();
    if (!mounted) return;
    setState(() {});
    if (GrowyPalette.isDark == dark) return;
    GrowyPalette.isDark = dark;
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Growy',
      debugShowCheckedModeBanner: false,
      theme: GrowyThemes.light,
      darkTheme: GrowyThemes.dark,
      themeMode: themeController.value,
      home: const _StartScreen(),
    );
  }
}

/// Opens Home when the user is still logged in from last time (Firebase keeps
/// the login on the device), otherwise the Welcome screen.
class _StartScreen extends StatefulWidget {
  const _StartScreen();

  @override
  State<_StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<_StartScreen> {
  // Created once: the theme switch rebuilds every screen, and a new Future
  // here would flash the spinner and rebuild Home from scratch.
  // The first value tells us whether a saved login was restored.
  final Future<User?> _savedLogin = FirebaseAuth.instance.authStateChanges().first;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<User?>(
      future: _savedLogin,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data != null ? const HomeScreen() : const WelcomeScreen();
      },
    );
  }
}
