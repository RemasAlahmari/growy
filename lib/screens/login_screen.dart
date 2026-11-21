import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'signup_screen.dart';
import '../services/auth_service.dart';
import '../core/motion/motion.dart';
import '../widgets/auth_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final error = await _authService.logIn(email: email, password: password);

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Logged in as $email')));

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  // "Forgot password?": opens a small box with the email (pre-filled from the
  // Email field). Firebase then emails a link to set a new password.
  Future<void> _openForgotPassword() async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => _ForgotPasswordDialog(
        initialEmail: _emailController.text.trim(),
        authService: _authService,
      ),
    );
    if (sent != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'If an account exists for this email, we sent a reset link. '
          'Check your inbox (and spam).',
        ),
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
                            title: 'Welcome Back!',
                            subtitle: 'Log in to keep leveling up',
                            gap: 24,
                          ),
                        ),
                        const SizedBox(height: 32),
                        GrowySlideIn(
                          index: 2,
                          child: GrowyField(
                            label: 'Email',
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
                          index: 4,
                          child: GrowyPrimaryButton(
                            label: 'Login',
                            onPressed: _handleLogin,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GrowySlideIn(
                          index: 5,
                          child: TextButton(
                            onPressed: _isLoading ? null : _openForgotPassword,
                            child: Text(
                              'Forgot password?',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
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

/// The "Reset password" box. Closes with true when the email was sent.
class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({
    required this.initialEmail,
    required this.authService,
  });

  final String initialEmail;
  final AuthService authService;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialEmail);
  bool _isSending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _controller.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email.');
      return;
    }
    setState(() {
      _isSending = true;
      _error = null;
    });
    final error = await widget.authService.sendPasswordReset(email);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _isSending = false;
        _error = error;
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Enter your account's email and we'll send you a link "
            'to set a new password.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            enabled: !_isSending,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              labelText: 'Email',
              hintText: 'you@example.com',
              prefixIcon: const Icon(Icons.mail_outline),
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isSending ? null : _send,
          child: _isSending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send'),
        ),
      ],
    );
  }
}
