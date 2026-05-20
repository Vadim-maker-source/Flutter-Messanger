import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../main.dart' show initCallsAfterLogin, AppColors;
import 'home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _api = ApiService();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _usernameCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if ([_emailCtrl, _passCtrl, _usernameCtrl, _nameCtrl].any((c) => c.text.trim().isEmpty)) {
      _snack('Заполните все поля');
      return;
    }
    setState(() => _loading = true);
    final result = await _api.register(
      _emailCtrl.text.trim(), _passCtrl.text,
      _usernameCtrl.text.trim(), _nameCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      final user = result['user'];
      await initCallsAfterLogin(user.id, user.displayName ?? user.username ?? '');
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      _snack(result['error'] ?? 'Ошибка регистрации');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: AppColors.surfaceAlt,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.darkAccent],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [BoxShadow(
                          color: AppColors.primary.withOpacity(0.4),
                          blurRadius: 20, offset: const Offset(0, 8),
                        )],
                      ),
                      child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 30),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text('Создать аккаунт',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white)),
                  const SizedBox(height: 6),
                  const Text('Заполните данные для регистрации',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AppColors.muted)),
                  const SizedBox(height: 36),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _field('Имя', _nameCtrl, Icons.person_outline_rounded, hint: 'Иван Иванов'),
                        const SizedBox(height: 14),
                        _field('Username', _usernameCtrl, Icons.alternate_email_rounded, hint: 'ivan'),
                        const SizedBox(height: 14),
                        _field('Email', _emailCtrl, Icons.email_outlined,
                            hint: 'you@example.com', type: TextInputType.emailAddress),
                        const SizedBox(height: 14),
                        _Label('Пароль'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _passCtrl,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _register(),
                          style: const TextStyle(color: Colors.white),
                          decoration: _dec('••••••••', Icons.lock_outline_rounded).copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                color: AppColors.muted, size: 20,
                              ),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _register,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _loading
                                ? const SizedBox(width: 20, height: 20,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('Зарегистрироваться',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('Уже есть аккаунт? ', style: TextStyle(color: AppColors.muted)),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Text('Войти',
                          style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
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

  Widget _field(String label, TextEditingController ctrl, IconData icon,
      {String hint = '', TextInputType type = TextInputType.text}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Label(label),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        keyboardType: type,
        textInputAction: TextInputAction.next,
        style: const TextStyle(color: Colors.white),
        decoration: _dec(hint, icon),
      ),
    ]);
  }

  InputDecoration _dec(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, color: AppColors.muted, size: 18),
    filled: true,
    fillColor: AppColors.surfaceAlt,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
    hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white70));
}
