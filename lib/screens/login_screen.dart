import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../main.dart' show initCallsAfterLogin, AppColors;
import 'register_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _api = ApiService();
  bool _loading = false;
  bool _obscure = true;
  String _error = '';

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Заполните все поля');
      return;
    }
    setState(() { _loading = true; _error = ''; });
    final result = await _api.login(email, pass);
    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      final user = result['user'];
      await initCallsAfterLogin(user.id, user.displayName ?? user.username ?? '');
      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      setState(() => _error = result['error'] ?? 'Ошибка входа');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // App icon
                  Center(
                    child: Container(
                      width: 76, height: 76,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F1F26),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Image.asset('assets/icon.png'),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Title
                  const Text('Добро пожаловать',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  const SizedBox(height: 6),
                  Text('Войдите, чтобы продолжить',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.5))),

                  const SizedBox(height: 36),

                  // Email
                  _SoftField(
                    controller: _emailCtrl,
                    hint: 'Email',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => setState(() => _error = ''),
                  ),
                  const SizedBox(height: 10),

                  // Password
                  _SoftField(
                    controller: _passCtrl,
                    hint: 'Пароль',
                    icon: Icons.lock_outline_rounded,
                    obscure: _obscure,
                    onChanged: (_) => setState(() => _error = ''),
                    onSubmitted: (_) => _login(),
                    suffix: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: Colors.white.withValues(alpha: 0.4),
                        size: 18,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),

                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_error,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Color(0xFFEF4444), fontSize: 13)),
                    ),
                  ],

                  const SizedBox(height: 22),

                  // Submit
                  Material(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: _loading ? null : _login,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('Войти',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Sign up link
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('Нет аккаунта? ',
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.4))),
                    GestureDetector(
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const RegisterScreen())),
                      child: const Text('Зарегистрироваться',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary)),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SoftField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const _SoftField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.obscure = false,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.white, fontSize: 14.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.3), fontSize: 14.5),
        prefixIcon: Icon(icon,
            size: 19, color: Colors.white.withValues(alpha: 0.4)),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFF1F1F26),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: AppColors.primary.withValues(alpha: 0.4), width: 1),
        ),
      ),
    );
  }
}
