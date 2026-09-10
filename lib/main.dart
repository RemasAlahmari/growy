import 'package:flutter/material.dart';
import 'screens/welcome_screen.dart';

void main() {
  runApp(const GrowyApp());
}

class GrowyApp extends StatelessWidget {
  const GrowyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Growy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF7CB79E),
        useMaterial3: true,
      ),
      home: const WelcomeScreen(),
    );
  }
}