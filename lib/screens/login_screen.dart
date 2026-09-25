import 'package:flutter/material.dart';

import 'signup_screen.dart';
import '../widgets/auth_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    // TODO: connect this to your FastAPI backend later.
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Logging in as $username...')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
                        const GrowyLogo(width: 93, height: 85),
                        const GrowyTitle(
                          title: 'Welcome Back!',
                          subtitle: 'Log in to keep leveling up',
                          gap: 24,
                        ),
                        const SizedBox(height: 32),
                        GrowyField(
                          label: 'Username or Email',
                          hint: 'you@example.com',
                          icon: Icons.mail_outline,
                          controller: _usernameController,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),
                        GrowyField(
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
                        const SizedBox(height: 28),
                        GrowyPrimaryButton(
                          label: 'Login',
                          onPressed: _handleLogin,
                        ),
                      ],
                    ),
                  ),
                ),
                GrowyFooterLink(
                  prefix: "Don't have an account?",
                  link: 'Sign Up',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SignUpScreen()),
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
