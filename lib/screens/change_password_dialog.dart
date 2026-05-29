import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../main.dart' show AppColors;

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});
  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

enum _Step { form, chooseMethod, verify, newPassword, success }
enum _Method { push, email }

class _ChangePasswordDialogState extends State<ChangePasswordDialog>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  _Step _step = _Step.form;
  _Method _method = _Method.push;
  bool _forgotMode = false;

  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _showOld = false;
  bool _showNew = false;

  String _generatedCode = '';
  final List<TextEditingController> _codeCtrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _codeFocus = List.generate(6, (_) => FocusNode());
  String _deliveredTo = '';
  String? _error;
  bool _loading = false;
  int _resendIn = 0;

  late final AnimationController _floatCtrl;

  @override
  void initState() {
    super.initState();
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    for (final c in _codeCtrls) {
      c.dispose();
    }
    for (final f in _codeFocus) {
      f.dispose();
    }
    _floatCtrl.dispose();
    super.dispose();
  }

  // Сервер генерирует код. Клиент знает только то что ввёл пользователь.
  Future<bool> _sendCode({required _Method method}) async {
    final resp = await _api.send2faCode(
      action: _forgotMode ? 'reset-password' : 'change-password',
      method: method == _Method.email ? 'email' : 'push',
    );
    if (resp != null && resp['deliveredTo'] is String) {
      _deliveredTo = resp['deliveredTo'] as String;
    }
    return resp != null && resp['success'] == true;
  }

  Future<void> _handleStartVerify() async {
    setState(() => _error = null);
    if (_oldCtrl.text.isEmpty) {
      return setState(() => _error = 'Введите текущий пароль');
    }
    if (_newCtrl.text.length < 6) {
      return setState(() => _error = 'Пароль должен быть не короче 6 символов');
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      return setState(() => _error = 'Пароли не совпадают');
    }
    if (_newCtrl.text == _oldCtrl.text) {
      return setState(() => _error = 'Новый пароль должен отличаться');
    }

    // В режиме "изменить пароль" с известным старым — 2FA не обязателен.
    // Сразу меняем пароль (старый сам по себе доказывает identity).
    setState(() => _loading = true);
    await _doChangePassword(_oldCtrl.text, _newCtrl.text);
  }

  void _handleForgot() {
    setState(() {
      _forgotMode = true;
      _step = _Step.chooseMethod;
      _error = null;
    });
  }

  Future<void> _handleChooseMethod(_Method method) async {
    setState(() {
      _method = method;
      _loading = true;
      _error = null;
    });
    final ok = await _sendCode(method: method);
    setState(() => _loading = false);

    if (!ok) {
      return setState(() => _error = method == _Method.email
          ? 'Не удалось отправить письмо'
          : 'Не удалось отправить код');
    }
    setState(() {
      _step = _Step.verify;
      _resendIn = 60;
    });
    _startResendTimer();
    Future.delayed(const Duration(milliseconds: 100),
        () => _codeFocus[0].requestFocus());
  }

  void _startResendTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted || _resendIn <= 0) return;
      setState(() => _resendIn--);
      if (_resendIn > 0) _startResendTimer();
    });
  }

  Future<void> _handleResend() async {
    if (_resendIn > 0) return;
    setState(() => _loading = true);
    final ok = await _sendCode(method: _method);
    setState(() => _loading = false);
    if (ok) {
      for (final c in _codeCtrls) {
        c.clear();
      }
      _codeFocus[0].requestFocus();
      setState(() => _resendIn = 60);
      _startResendTimer();
    }
  }

  void _onCodeChange(int idx, String val) {
    if (val.length == 1 && idx < 5) {
      _codeFocus[idx + 1].requestFocus();
    }
    final code = _codeCtrls.map((c) => c.text).join();
    if (code.length == 6) _verifyCode(code);
  }

  /// При forgot-режиме — отправляем код на сервер для проверки одним запросом
  /// со сменой пароля, чтобы сервер атомарно валидировал и менял.
  /// Здесь только переход к экрану ввода нового пароля.
  void _verifyCode(String code) {
    setState(() {
      _enteredCode = code;
      _error = null;
      _step = _Step.newPassword;
    });
  }

  String _enteredCode = '';

  Future<void> _doChangePassword(String oldPwd, String newPwd) async {
    setState(() => _loading = true);
    final ok = await _api.changePassword(
      oldPassword: oldPwd,
      newPassword: newPwd,
      code: _forgotMode ? _enteredCode : null,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok.success) {
      setState(() => _step = _Step.success);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.pop(context);
      });
    } else {
      setState(() => _error = ok.error ?? 'Ошибка смены пароля');
    }
  }

  Future<void> _submitNewPassword() async {
    setState(() => _error = null);
    if (_newCtrl.text.length < 6) {
      return setState(() => _error = 'Пароль должен быть не короче 6 символов');
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      return setState(() => _error = 'Пароли не совпадают');
    }
    await _doChangePassword('', _newCtrl.text);
  }

  void _handleBack() {
    setState(() => _error = null);
    if (_step == _Step.verify) {
      setState(() => _step = _forgotMode ? _Step.chooseMethod : _Step.form);
    } else if (_step == _Step.chooseMethod || _step == _Step.newPassword) {
      setState(() {
        _step = _Step.form;
        if (_step == _Step.chooseMethod) _forgotMode = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF16161B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header with floating 3D lock
          Container(
            height: 160,
            decoration: const BoxDecoration(
              color: Color(0xFF1C1C24),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Stack(children: [
              // Floating lock animation
              Center(
                child: AnimatedBuilder(
                  animation: _floatCtrl,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(0, -6 + 12 * _floatCtrl.value),
                    child: child,
                  ),
                  child: Image.asset('assets/3dlock.png', width: 100, height: 100),
                ),
              ),
              // Top controls
              Positioned(
                top: 12, left: 12, right: 12,
                child: Row(children: [
                  if (_step == _Step.verify ||
                      _step == _Step.chooseMethod ||
                      _step == _Step.newPassword)
                    _CircleBtn(
                      icon: Icons.arrow_back,
                      onTap: _handleBack,
                    )
                  else
                    const SizedBox(width: 36),
                  const Spacer(),
                  _CircleBtn(
                    icon: Icons.close,
                    onTap: () => Navigator.pop(context),
                  ),
                ]),
              ),
            ]),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _buildStepContent(),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case _Step.form:        return _buildForm();
      case _Step.chooseMethod: return _buildChooseMethod();
      case _Step.verify:      return _buildVerify();
      case _Step.newPassword: return _buildNewPassword();
      case _Step.success:     return _buildSuccess();
    }
  }

  Widget _buildForm() {
    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: Text('Сменить пароль',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white))),
        const SizedBox(height: 4),
        Center(child: Text('Введите текущий и новый пароль',
            style: TextStyle(
                fontSize: 13, color: Colors.white.withValues(alpha: 0.5)))),
        const SizedBox(height: 22),
        _PasswordField(
          label: 'Текущий пароль',
          controller: _oldCtrl,
          show: _showOld,
          onToggle: () => setState(() => _showOld = !_showOld),
        ),
        const SizedBox(height: 10),
        _PasswordField(
          label: 'Новый пароль',
          controller: _newCtrl,
          show: _showNew,
          onToggle: () => setState(() => _showNew = !_showNew),
        ),
        const SizedBox(height: 10),
        _PasswordField(
          label: 'Повторите новый пароль',
          controller: _confirmCtrl,
          show: _showNew,
          onToggle: () => setState(() => _showNew = !_showNew),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          _ErrorBox(_error!),
        ],
        const SizedBox(height: 18),
        _PrimaryButton(
          loading: _loading,
          label: 'Продолжить',
          onTap: _handleStartVerify,
        ),
        const SizedBox(height: 12),
        Center(child: TextButton(
          onPressed: _loading ? null : _handleForgot,
          child: Text('Забыли пароль?',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
        )),
      ],
    );
  }

  Widget _buildChooseMethod() {
    return Column(
      key: const ValueKey('choose'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: Text('Восстановление пароля',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white))),
        const SizedBox(height: 4),
        Center(child: Text('Куда отправить код?',
            style: TextStyle(
                fontSize: 13, color: Colors.white.withValues(alpha: 0.5)))),
        const SizedBox(height: 22),
        Row(children: [
          Expanded(child: _MethodCard(
            icon: Icons.notifications_outlined,
            title: 'Push',
            subtitle: 'В приложение',
            onTap: _loading ? null : () => _handleChooseMethod(_Method.push),
          )),
          const SizedBox(width: 12),
          Expanded(child: _MethodCard(
            icon: Icons.email_outlined,
            title: 'Email',
            subtitle: 'На вашу почту',
            onTap: _loading ? null : () => _handleChooseMethod(_Method.email),
          )),
        ]),
        if (_loading) ...[
          const SizedBox(height: 18),
          const Center(child: SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          )),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          _ErrorBox(_error!),
        ],
      ],
    );
  }

  Widget _buildVerify() {
    return Column(
      key: const ValueKey('verify'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: Text('Введите код',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white))),
        const SizedBox(height: 4),
        Center(child: Text(
          _forgotMode && _method == _Method.email
              ? 'Код отправлен на ${_deliveredTo.isNotEmpty ? _deliveredTo : "почту"}'
              : '6-значный код в push-уведомлении',
          style: TextStyle(
              fontSize: 13, color: Colors.white.withValues(alpha: 0.5)),
          textAlign: TextAlign.center,
        )),
        const SizedBox(height: 22),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (idx) => _CodeBox(
              controller: _codeCtrls[idx],
              focusNode: _codeFocus[idx],
              onChanged: (v) => _onCodeChange(idx, v),
              onBackspace: () {
                if (_codeCtrls[idx].text.isEmpty && idx > 0) {
                  _codeFocus[idx - 1].requestFocus();
                  _codeCtrls[idx - 1].clear();
                }
              },
              error: _error != null,
            ))),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Center(child: Text(_error!,
              style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13))),
        ],
        const SizedBox(height: 16),
        Center(child: TextButton(
          onPressed: _resendIn > 0 || _loading ? null : _handleResend,
          child: Text(
            _resendIn > 0 ? 'Повторно через $_resendIn с' : 'Отправить код повторно',
            style: TextStyle(
              color: _resendIn > 0
                  ? Colors.white.withValues(alpha: 0.3)
                  : AppColors.primary,
              fontSize: 13,
            ),
          ),
        )),
        if (_loading)
          const Center(child: Padding(
            padding: EdgeInsets.only(top: 6),
            child: SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary)),
          )),
      ],
    );
  }

  Widget _buildNewPassword() {
    return Column(
      key: const ValueKey('new-password'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: Text('Новый пароль',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white))),
        const SizedBox(height: 4),
        Center(child: Text('Придумайте новый пароль',
            style: TextStyle(
                fontSize: 13, color: Colors.white.withValues(alpha: 0.5)))),
        const SizedBox(height: 22),
        _PasswordField(
          label: 'Новый пароль',
          controller: _newCtrl,
          show: _showNew,
          onToggle: () => setState(() => _showNew = !_showNew),
        ),
        const SizedBox(height: 10),
        _PasswordField(
          label: 'Повторите пароль',
          controller: _confirmCtrl,
          show: _showNew,
          onToggle: () => setState(() => _showNew = !_showNew),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          _ErrorBox(_error!),
        ],
        const SizedBox(height: 18),
        _PrimaryButton(
          loading: _loading,
          label: 'Сохранить пароль',
          onTap: _submitNewPassword,
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      key: const ValueKey('success'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56, height: 56,
          decoration: const BoxDecoration(
              color: AppColors.primary, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 30),
        ),
        const SizedBox(height: 14),
        const Text('Пароль обновлён',
            style: TextStyle(
                fontSize: 19, fontWeight: FontWeight.w600, color: Colors.white)),
        const SizedBox(height: 4),
        Text('Можете использовать новый пароль',
            style: TextStyle(
                fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
      ],
    );
  }
}

// ─── Components ──────────────────────────────────────────────────────────────

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: 0.3),
    shape: const CircleBorder(),
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(width: 36, height: 36,
          child: Icon(icon, size: 16,
              color: Colors.white.withValues(alpha: 0.7))),
    ),
  );
}

class _PasswordField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool show;
  final VoidCallback onToggle;
  const _PasswordField({
    required this.label,
    required this.controller,
    required this.show,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 6),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
      ),
      TextField(
        controller: controller,
        obscureText: !show,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFF1F1F26),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          suffixIcon: IconButton(
            icon: Icon(
              show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 18,
              color: Colors.white.withValues(alpha: 0.4),
            ),
            onPressed: onToggle,
          ),
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
            borderSide: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.4), width: 1),
          ),
        ),
      ),
    ]);
  }
}

class _CodeBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;
  final bool error;
  const _CodeBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBackspace,
    this.error = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44, height: 54,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (e) {
          if (e is KeyDownEvent &&
              e.logicalKey == LogicalKeyboardKey.backspace &&
              controller.text.isEmpty) {
            onBackspace();
          }
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 1,
          style: const TextStyle(
              color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            counter: const SizedBox.shrink(),
            counterText: '',
            filled: true,
            fillColor: controller.text.isNotEmpty
                ? AppColors.primary.withValues(alpha: 0.1)
                : const Color(0xFF1F1F26),
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: error
                  ? const BorderSide(color: Color(0xFFEF4444), width: 1)
                  : controller.text.isNotEmpty
                      ? BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.5),
                          width: 1)
                      : BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.6), width: 1),
            ),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(1),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1F1F26),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
          child: Column(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(height: 8),
            Text(title,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
          ]),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final bool loading;
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({
    required this.loading,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 50,
          alignment: Alignment.center,
          child: loading
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String text;
  const _ErrorBox(this.text);
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFEF4444).withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
  );
}
