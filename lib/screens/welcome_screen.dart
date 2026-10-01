import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'login_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const GrowyCircle(
            color: AppColors.secondary,
            size: 340,
            left: -140,
            top: -150,
          ),
          const GrowyCircle(
            color: AppColors.primary,
            size: 340,
            right: -120,
            top: -150,
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),
                const Flexible(
                  flex: 6,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: GrowyLogo(width: 230, height: 257),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Growy',
                  style: GoogleFonts.fraunces(
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Level Up Your Life',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                    color: AppColors.secondaryText,
                  ),
                ),
                const Spacer(flex: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 325),
                    child: GrowyPrimaryButton(
                      label: 'Get Started',
                      height: 72,
                      fontSize: 18,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
