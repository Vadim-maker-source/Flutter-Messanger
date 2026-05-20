import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../main.dart' show AppColors, disposeCallsOnLogout;
import 'login_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _api = ApiService();
  User? _user;
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final user = await _api.getProfile();
    if (mounted) setState(() { _user = user; _loading = false; });
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    final result = await _api.uploadFile(File(picked.path), 'image/jpeg');
    if (!mounted) return;
    if (result != null) {
      final updated = await _api.updateProfile(avatarUrl: result['url'] as String);
      if (mounted && updated != null) setState(() => _user = updated);
    }
    setState(() => _uploading = false);
  }

  void _editProfile() {
    final nameCtrl = TextEditingController(text: _user?.displayName);
    final bioCtrl = TextEditingController(text: _user?.bio);
    final statusCtrl = TextEditingController(text: _user?.status);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Text('Редактировать профиль',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.muted),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
          const SizedBox(height: 16),
          _EditField('Имя', nameCtrl, Icons.person_outline_rounded),
          const SizedBox(height: 12),
          _EditField('О себе', bioCtrl, Icons.info_outline_rounded, maxLines: 3),
          const SizedBox(height: 12),
          _EditField('Статус', statusCtrl, Icons.circle_outlined),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final updated = await _api.updateProfile(
                displayName: nameCtrl.text.trim(),
                bio: bioCtrl.text.trim(),
                status: statusCtrl.text.trim(),
              );
              if (mounted && updated != null) setState(() => _user = updated);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Сохранить', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  Future<void> _logout() async {
    final userId = _user?.id ?? '';
    await _api.clearToken();
    if (userId.isNotEmpty) disposeCallsOnLogout(userId);
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: [
          if (_user != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: _editProfile,
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _user == null
              ? const Center(child: Text('Ошибка загрузки'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(children: [
                    // Avatar
                    Stack(alignment: Alignment.bottomRight, children: [
                      GestureDetector(
                        onTap: _pickAvatar,
                        child: Container(
                          width: 96, height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.primary, width: 2),
                          ),
                          child: ClipOval(
                            child: _uploading
                                ? Container(
                                    color: AppColors.surfaceAlt,
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                          color: AppColors.primary, strokeWidth: 2),
                                    ),
                                  )
                                : _user!.avatarUrl != null
                                    ? Image.network(_user!.avatarUrl!, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _avatarFallback())
                                    : _avatarFallback(),
                          ),
                        ),
                      ),
                      Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.background, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    Text(_user!.displayName,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('@${_user!.username}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(_user!.email,
                        style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                    const SizedBox(height: 20),

                    // Info card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (_user!.bio != null && _user!.bio!.isNotEmpty) ...[
                          _InfoRow(Icons.info_outline_rounded, 'О себе', _user!.bio!),
                          const SizedBox(height: 12),
                        ],
                        if (_user!.status != null && _user!.status!.isNotEmpty)
                          _InfoRow(Icons.circle_outlined, 'Статус', _user!.status!),
                        if ((_user!.bio == null || _user!.bio!.isEmpty) &&
                            (_user!.status == null || _user!.status!.isEmpty))
                          const Text('Нет информации',
                              style: TextStyle(color: AppColors.muted, fontSize: 13)),
                      ]),
                    ),
                    const SizedBox(height: 32),

                    // Logout
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text('Выйти из аккаунта'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: const BorderSide(color: Color(0x33EF4444)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ]),
                ),
    );
  }

  Widget _avatarFallback() => Container(
    color: AppColors.surfaceAlt,
    child: Center(
      child: Text(
        _user!.displayName.isNotEmpty ? _user!.displayName[0].toUpperCase() : '?',
        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: AppColors.muted),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        Text(value, style: const TextStyle(fontSize: 14)),
      ])),
    ],
  );
}

class _EditField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final IconData icon;
  final int maxLines;
  const _EditField(this.label, this.ctrl, this.icon, {this.maxLines = 1});
  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    maxLines: maxLines,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.muted),
      prefixIcon: Icon(icon, color: AppColors.muted, size: 18),
      filled: true,
      fillColor: AppColors.surfaceAlt,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
    ),
  );
}
