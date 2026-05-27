import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../main.dart' show AppColors;

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});
  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _api = ApiService();
  bool _loading = true;
  bool _saving = false;

  late final TextEditingController _name;
  late final TextEditingController _status;
  late final TextEditingController _bio;
  late final TextEditingController _telegram;
  late final TextEditingController _vk;
  late final TextEditingController _github;
  late final TextEditingController _website;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _status = TextEditingController();
    _bio = TextEditingController();
    _telegram = TextEditingController();
    _vk = TextEditingController();
    _github = TextEditingController();
    _website = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _status.dispose();
    _bio.dispose();
    _telegram.dispose();
    _vk.dispose();
    _github.dispose();
    _website.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = await _api.getProfile();
    if (!mounted) return;
    if (user != null) {
      _name.text = user.displayName;
      _status.text = user.status ?? '';
      _bio.text = user.bio ?? '';
      _telegram.text = user.socialLinks?.telegram ?? '';
      _vk.text = user.socialLinks?.vk ?? '';
      _github.text = user.socialLinks?.github ?? '';
      _website.text = user.socialLinks?.website ?? '';
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите имя')));
      return;
    }
    setState(() => _saving = true);
    final updated = await _api.updateProfile(
      displayName: _name.text.trim(),
      bio: _bio.text.trim(),
      status: _status.text.trim(),
      socialLinks: {
        'telegram': _telegram.text.trim(),
        'vk': _vk.text.trim(),
        'github': _github.text.trim(),
        'website': _website.text.trim(),
      },
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (updated != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Профиль обновлён')));
      Navigator.pop(context, updated);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white.withValues(alpha: 0.7)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Редактировать',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          if (_saving)
            const Padding(padding: EdgeInsets.all(14),
                child: SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary)))
          else
            TextButton(
              onPressed: _save,
              child: const Text('Сохранить',
                  style: TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _Group('Основное'),
                _Field(label: 'Имя', controller: _name, hint: 'Ваше имя'),
                const SizedBox(height: 12),
                _Field(label: 'Статус', controller: _status,
                    hint: 'Что у вас на уме?'),
                const SizedBox(height: 12),
                _Field(label: 'О себе', controller: _bio,
                    hint: 'Расскажите немного о себе...', maxLines: 4),

                const SizedBox(height: 28),
                const _Group('Социальные сети'),
                _Field(label: 'Telegram', controller: _telegram,
                    hint: 'https://t.me/username'),
                const SizedBox(height: 12),
                _Field(label: 'VK', controller: _vk,
                    hint: 'https://vk.com/username'),
                const SizedBox(height: 12),
                _Field(label: 'GitHub', controller: _github,
                    hint: 'https://github.com/username'),
                const SizedBox(height: 12),
                _Field(label: 'Сайт', controller: _website,
                    hint: 'https://example.com'),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

class _Group extends StatelessWidget {
  final String title;
  const _Group(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
    child: Text(title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.35),
          letterSpacing: 1.4,
        )),
  );
}

class _Field extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController controller;
  final int maxLines;
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(label, style: TextStyle(
            fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
      ),
      TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white, fontSize: 14.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
