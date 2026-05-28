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
  int _step = 1;
  bool _loading = false;
  bool _obscure = true;
  String _error = '';

  final _usernameCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _api = ApiService();

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _next() {
    setState(() {
      _step++;
      _error = '';
    });
  }

  void _back() {
    if (_step == 1) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _step--;
      _error = '';
    });
  }

  Future<void> _register() async {
    if (_passCtrl.text.length < 6) {
      setState(() => _error = 'Пароль должен быть не менее 6 символов');
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    final result = await _api.register(
      _emailCtrl.text.trim(),
      _passCtrl.text,
      _usernameCtrl.text.trim(),
      _nameCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result['success'] == true) {
      final user = result['user'];
      await initCallsAfterLogin(
          user.id, user.displayName ?? user.username ?? '');
      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      setState(() => _error = result['error'] ?? 'Ошибка регистрации');
    }
  }

  bool get _canNext {
    switch (_step) {
      case 1:
        return _usernameCtrl.text.trim().isNotEmpty;
      case 2:
        return _nameCtrl.text.trim().isNotEmpty;
      case 3:
        return _emailCtrl.text.contains('@');
      case 4:
        return _passCtrl.text.length >= 6;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back,
                        color: Colors.white.withValues(alpha: 0.7)),
                    onPressed: _back,
                  ),
                  Expanded(child: _ProgressBar(step: _step, total: 4)),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) {
                      return FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.04, 0),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: _buildStep(),
                    ),
                  ),
                ),
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_error,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Color(0xFFEF4444), fontSize: 13)),
                      ),
                    ),

                  Material(
                    color: _canNext
                        ? AppColors.primary
                        : const Color(0xFF1F1F26),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: !_canNext || _loading
                          ? null
                          : (_step == 4 ? _register : _next),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : Text(
                                _step == 4 ? 'Создать аккаунт' : 'Далее',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: _canNext
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.4)),
                              ),
                      ),
                    ),
                  ),

                  if (_step == 1) ...[
                    const SizedBox(height: 14),
                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: RichText(
                          text: TextSpan(children: [
                            TextSpan(
                              text: 'Уже есть аккаунт? ',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.4)),
                            ),
                            const TextSpan(
                              text: 'Войти',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 1:
        return _StepBody(
          title: 'Придумайте ник',
          subtitle: 'Уникальный идентификатор в системе',
          field: _SoftField(
            controller: _usernameCtrl,
            hint: 'username',
            icon: Icons.alternate_email_rounded,
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
        );
      case 2:
        return _StepBody(
          title: 'Как вас зовут?',
          subtitle: 'Имя, которое увидят другие',
          field: _SoftField(
            controller: _nameCtrl,
            hint: 'Имя',
            icon: Icons.person_outline_rounded,
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
        );
      case 3:
        return _StepBody(
          title: 'Email',
          subtitle: 'Понадобится для восстановления пароля',
          field: _SoftField(
            controller: _emailCtrl,
            hint: 'email@example.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
        );
      case 4:
        return _StepBody(
          title: 'Пароль',
          subtitle: 'Минимум 6 символов',
          field: _SoftField(
            controller: _passCtrl,
            hint: 'Пароль',
            icon: Icons.lock_outline_rounded,
            obscure: _obscure,
            autofocus: true,
            onChanged: (_) => setState(() {}),
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
        );
      default:
        return const SizedBox();
    }
  }
}

class _StepBody extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget field;
  const _StepBody({
    required this.title,
    required this.subtitle,
    required this.field,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Text(title,
            style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
        const SizedBox(height: 8),
        Text(subtitle,
            style: TextStyle(
                fontSize: 14, color: Colors.white.withValues(alpha: 0.5))),
        const SizedBox(height: 28),
        field,
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int step;
  final int total;
  const _ProgressBar({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: List.generate(total, (i) {
          final filled = i < step;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              height: 4,
              margin: EdgeInsets.only(right: i < total - 1 ? 6 : 0),
              decoration: BoxDecoration(
                color: filled
                    ? AppColors.primary
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        }),
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
  final bool autofocus;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;

  const _SoftField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.obscure = false,
    this.autofocus = false,
    this.suffix,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      autofocus: autofocus,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.3), fontSize: 15),
        prefixIcon: Icon(icon,
            size: 20, color: Colors.white.withValues(alpha: 0.4)),
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
