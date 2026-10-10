import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../services/auth_service.dart';

import 'avatar_customizer_screen.dart';
import 'login_screen.dart';
import '../core/motion/motion.dart';
import '../widgets/auth_widgets.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _obscurePassword = true;
  bool _isLoading = false;
  GrowyGender? _gender;
  String? _genderError;

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleSignUp() async {
    final email = _emailController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (_gender == null) setState(() => _genderError = 'Please choose your gender');
    if (email.isEmpty || username.isEmpty || password.isEmpty || _gender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final error = await _authService.signUp(
      email: email,
      password: password,
      username: username,
      gender: _gender!.apiValue,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const AvatarCustomizerScreen(isFirstSetup: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          ...bottomCircles(),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 48),
                        GrowySlideIn(
                          index: 0,
                          child: const GrowyLogo(width: 93, height: 85),
                        ),
                        GrowySlideIn(
                          index: 1,
                          child: const GrowyTitle(
                            title: 'Create Account',
                            subtitle: 'Start your first streak today',
                            gap: 24,
                          ),
                        ),
                        const SizedBox(height: 32),
                        GrowySlideIn(
                          index: 2,
                          child: GrowyField(
                            label: 'Email Address',
                            hint: 'you@example.com',
                            icon: Icons.mail_outline,
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                          ),
                        ),
                        const SizedBox(height: 16),
                        GrowySlideIn(
                          index: 3,
                          child: GrowyField(
                            label: 'Username',
                            hint: 'username',
                            icon: Icons.person_outline,
                            controller: _usernameController,
                          ),
                        ),
                        const SizedBox(height: 16),
                        GrowySlideIn(
                          index: 4,
                          child: GrowyGenderPicker(
                            value: _gender,
                            errorText: _genderError,
                            onChanged: (g) => setState(() {
                              _gender = g;
                              _genderError = null;
                            }),
                          ),
                        ),
                        const SizedBox(height: 16),
                        GrowySlideIn(
                          index: 5,
                          child: GrowyField(
                            label: 'Password',
                            hint: '••••••••',
                            icon: Icons.lock_outline,
                            controller: _passwordController,
                            isPassword: true,
                            obscure: _obscurePassword,
                            onToggleObscure: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        GrowySlideIn(
                          index: 6,
                          child: GrowyPrimaryButton(
                            label: 'Sign Up',
                            onPressed: _handleSignUp,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                GrowyFooterLink(
                  prefix: 'Already have an account?',
                  link: 'Log in',
                  onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
          Positioned(
            top: 4,
            left: 4,
            child: SafeArea(
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: AppColors.textDark),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}