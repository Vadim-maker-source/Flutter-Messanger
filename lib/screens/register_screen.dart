import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../main.dart' show initCallsAfterLogin, AppColors;
import 'home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  int _step = 1;
  bool _loading = false;
  bool _obscure = true;
  String _error = '';

  final _usernameCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _api = ApiService();

  late final AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
            begin: const Offset(0.08, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _usernameCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _nextStep() async {
    await _animCtrl.reverse();
    setState(() { _step++; _error = ''; });
    _animCtrl.forward();
  }

  void _prevStep() async {
    await _animCtrl.reverse();
    setState(() { _step--; _error = ''; });
    _animCtrl.forward();
  }

  Future<void> _register() async {
    if (_passCtrl.text.length < 6) {
      setState(() => _error = 'Пароль должен быть не менее 6 символов');
      return;
    }
    setState(() { _loading = true; _error = ''; });
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
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      setState(() => _error = result['error'] ?? 'Ошибка регистрации');
    }
  }

  bool get _canNext {
    switch (_step) {
      case 1: return _usernameCtrl.text.trim().isNotEmpty;
      case 2: return _nameCtrl.text.trim().isNotEmpty;
      case 3: return _emailCtrl.text.contains('@');
      case 4: return _passCtrl.text.length >= 6;
      default: return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(children: [
        // Glow effects like web version
        Positioned(top: -80, right: -80,
            child: Container(
                width: 300, height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.12),
                ))),
        Positioned(bottom: -80, left: -80,
            child: Container(
                width: 250, height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.darkAccent.withValues(alpha: 0.08),
                ))),

        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121214),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Progress bar
                      Row(children: List.generate(4, (i) => Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                          height: 4,
                          margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                          decoration: BoxDecoration(
                            color: i < _step
                                ? AppColors.primary
                                : AppColors.border,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: i < _step ? [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.5),
                                blurRadius: 6,
                              )
                            ] : null,
                          ),
                        ),
                      ))),
                      const SizedBox(height: 32),

                      // Step content with animation
                      FadeTransition(
                        opacity: _fadeAnim,
                        child: SlideTransition(
                          position: _slideAnim,
                          child: _buildStep(),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Sign in link
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('Уже есть аккаунт? ',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontSize: 13)),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Text('Войти',
                              style: TextStyle(
                                  color: AppColors.secondary,
                                  fontSize: 13,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppColors.secondary)),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 1: return _StepContent(
        title: 'Как тебя звать?',
        subtitle: 'Придумай уникальный никнейм',
        onNext: _canNext ? _nextStep : null,
        canNext: _canNext,
        child: _StepInput(
          controller: _usernameCtrl,
          icon: Icons.alternate_email_rounded,
          hint: 'username',
          type: TextInputType.text,
          onChanged: (_) => setState(() {}),
          onSubmitted: _canNext ? (_) => _nextStep() : null,
        ),
      );
      case 2: return _StepContent(
        title: 'Твоё имя',
        subtitle: 'Как тебя будут видеть друзья',
        onNext: _canNext ? _nextStep : null,
        onBack: _prevStep,
        canNext: _canNext,
        child: _StepInput(
          controller: _nameCtrl,
          icon: Icons.person_outline_rounded,
          hint: 'Имя или ник',
          onChanged: (_) => setState(() {}),
          onSubmitted: _canNext ? (_) => _nextStep() : null,
        ),
      );
      case 3: return _StepContent(
        title: 'Почта',
        subtitle: 'Для защиты твоего аккаунта',
        onNext: _canNext ? _nextStep : null,
        onBack: _prevStep,
        canNext: _canNext,
        child: _StepInput(
          controller: _emailCtrl,
          icon: Icons.email_outlined,
          hint: 'email@example.com',
          type: TextInputType.emailAddress,
          onChanged: (_) => setState(() {}),
          onSubmitted: _canNext ? (_) => _nextStep() : null,
        ),
      );
      case 4: return _StepContent(
        title: 'Пароль',
        subtitle: 'Придумай что-нибудь надёжное',
        onNext: _canNext && !_loading ? _register : null,
        onBack: _prevStep,
        canNext: _canNext,
        isLast: true,
        loading: _loading,
        child: Column(children: [
          _StepInput(
            controller: _passCtrl,
            icon: Icons.lock_outline_rounded,
            hint: '••••••••',
            obscure: _obscure,
            onChanged: (_) => setState(() {}),
            onSubmitted: _canNext && !_loading ? (_) => _register() : null,
            suffix: IconButton(
              icon: Icon(
                _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: AppColors.muted, size: 20,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x1AEF4444),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x33EF4444)),
              ),
              child: Text(_error,
                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
            ),
          ],
        ]),
      );
      default: return const SizedBox();
    }
  }
}

class _StepContent extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onNext;
  final VoidCallback? onBack;
  final bool canNext;
  final bool isLast;
  final bool loading;
  final Widget child;

  const _StepContent({
    required this.title,
    required this.subtitle,
    this.onNext,
    this.onBack,
    this.canNext = false,
    this.isLast = false,
    this.loading = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title,
          style: const TextStyle(
              fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white)),
      const SizedBox(height: 6),
      Text(subtitle,
          style: TextStyle(
              fontSize: 14, color: Colors.white.withValues(alpha: 0.5))),
      const SizedBox(height: 24),
      child,
      const SizedBox(height: 20),
      Row(children: [
        if (onBack != null) ...[
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.chevron_left_rounded,
                  color: Colors.white, size: 24),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: canNext ? 4 : 0,
                shadowColor: AppColors.primary.withValues(alpha: 0.4),
              ),
              child: loading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(
                        isLast ? 'Создать аккаунт' : 'Далее',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isLast ? Icons.check_circle_outline_rounded : Icons.arrow_forward_rounded,
                        size: 18,
                      ),
                    ]),
            ),
          ),
        ),
      ]),
    ]);
  }
}

class _StepInput extends StatelessWidget {
  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final TextInputType type;
  final bool obscure;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  const _StepInput({
    required this.controller,
    required this.icon,
    required this.hint,
    this.type = TextInputType.text,
    this.obscure = false,
    this.onChanged,
    this.onSubmitted,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: type,
      obscureText: obscure,
      autofocus: true,
      textInputAction:
          onSubmitted != null ? TextInputAction.done : TextInputAction.next,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 15),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
