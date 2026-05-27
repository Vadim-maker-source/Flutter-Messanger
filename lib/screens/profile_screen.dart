import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show AppColors, disposeCallsOnLogout;
import '../models/user.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'settings_screen.dart';

/// Свой профиль — портирован 1-в-1 с веб-страницы `app/(root)/profile/[type]/page.tsx`
/// для случая `isOwnProfile === true`.
///
/// Структура совпадает с экраном профиля собеседника, но без блока action-кнопок
/// (Чат / Звонок / Видео и т.д.) и без табов «Общие чаты» / «Медиа» — для своего
/// профиля их нет ни на вебе, ни здесь.
///
/// В шапке справа — два action-icon'а: edit (карандаш, открывает modal-bottom-sheet
/// редактирования имени/био/статуса/соцссылок) и settings (шестерёнка, открывает
/// `SettingsScreen`).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _violet = Color(0xFF7166D8);

  final _api = ApiService();
  User? _user;
  bool _loading = true;
  bool _uploadingAvatar = false;

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

  // ─── Helpers ─────────────────────────────────────────────────────────────
  String _formatDate(DateTime dt) =>
      DateFormat('d MMMM y', 'ru').format(dt.toLocal());

  String _formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return '';
    final diff = DateTime.now().difference(lastSeen.toLocal());
    if (diff.inMinutes < 1) return 'только что';
    if (diff.inMinutes < 60) return 'был(а) ${diff.inMinutes} мин. назад';
    if (diff.inHours < 24) return 'был(а) ${diff.inHours} ч. назад';
    if (diff.inDays < 7) return 'был(а) ${diff.inDays} д. назад';
    return 'был(а) ${DateFormat('d MMM', 'ru').format(lastSeen.toLocal())}';
  }

  // ─── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _user == null
              ? const Center(
                  child: Text('Не удалось загрузить профиль',
                      style: TextStyle(color: Colors.white70)))
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    return Column(children: [
      _buildHeader(),
      Expanded(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildProfileHeader(),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildInfoSection(),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ]);
  }

  // ─── Sticky header ───────────────────────────────────────────────────────
  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF121214).withValues(alpha: 0.5),
          border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(children: [
          IconButton(
            icon: Icon(Icons.arrow_back,
                color: Colors.white.withValues(alpha: 0.6)),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text('Профиль',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: Icon(Icons.edit_outlined,
                color: Colors.white.withValues(alpha: 0.6)),
            tooltip: 'Редактировать',
            onPressed: _editProfile,
          ),
          IconButton(
            icon: Icon(Icons.settings_outlined,
                color: Colors.white.withValues(alpha: 0.6)),
            tooltip: 'Настройки',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()))
                .then((_) => _load()),
          ),
        ]),
      ),
    );
  }

  // ─── Profile header card ─────────────────────────────────────────────────
  Widget _buildProfileHeader() {
    final user = _user!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(children: [
        // Avatar with online dot + camera overlay
        GestureDetector(
          onTap: _pickAvatar,
          child: Stack(children: [
            Container(
              width: 112, height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.2),
                    AppColors.darkAccent.withValues(alpha: 0.2),
                  ],
                ),
              ),
              child: ClipOval(
                child: _uploadingAvatar
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary, strokeWidth: 2))
                    : (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
                        ? Image.network(user.avatarUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, e, s) => _avatarFallback())
                        : _avatarFallback(),
              ),
            ),
            // Online indicator
            Positioned(
              bottom: 4, right: 4,
              child: Container(
                width: 18, height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF22C55E),
                  border: Border.all(color: const Color(0xFF0A0A0C), width: 3),
                ),
              ),
            ),
            // Camera overlay (corner)
            Positioned(
              bottom: 0, left: 0,
              child: Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                  border: Border.all(
                      color: const Color(0xFF0A0A0C), width: 2),
                ),
                child: const Icon(Icons.camera_alt,
                    size: 14, color: Colors.white),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        // Display name + «Это вы» badge
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(user.displayName.isNotEmpty
                    ? user.displayName : user.username,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text('Это вы',
                  style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFA78BFA),
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Status text
        const Text('В сети',
            style: TextStyle(fontSize: 14, color: Color(0xFF22C55E))),
        if (user.status != null && user.status!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(user.status!,
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.5))),
        ],
      ]),
    );
  }

  Widget _avatarFallback() {
    final user = _user!;
    final letter = user.displayName.isNotEmpty
        ? user.displayName[0].toUpperCase()
        : user.username.isNotEmpty
            ? user.username[0].toUpperCase()
            : '?';
    return Container(
      alignment: Alignment.center,
      child: Text(letter,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.bold)),
    );
  }

  // ─── Info section ────────────────────────────────────────────────────────
  Widget _buildInfoSection() {
    final user = _user!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          icon: Icons.tag,
          title: 'Имя пользователя',
          child: Text('@${user.username}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600)),
        ),
        if (user.bio != null && user.bio!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Card(
            icon: Icons.person_outline,
            title: 'О себе',
            child: SelectableText(user.bio!,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 15,
                    height: 1.5)),
          ),
        ],
        if (user.socialLinks != null && !user.socialLinks!.isEmpty) ...[
          const SizedBox(height: 12),
          _Card(
            icon: Icons.link,
            title: 'Соцсети и ссылки',
            child: _buildSocialLinks(user.socialLinks!),
          ),
        ],
        const SizedBox(height: 12),
        _Card(
          icon: Icons.email_outlined,
          title: 'Контактная информация',
          child: Row(children: [
            Icon(Icons.email_outlined,
                size: 14, color: Colors.white.withValues(alpha: 0.4)),
            const SizedBox(width: 6),
            Expanded(
              child: SelectableText(user.email,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 15)),
            ),
          ]),
        ),
        if (user.createdAt != null) ...[
          const SizedBox(height: 12),
          _Card(
            icon: Icons.calendar_today_outlined,
            title: 'Зарегистрирован',
            child: Text(_formatDate(user.createdAt!),
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 15)),
          ),
        ],
        if (user.stats != null) ...[
          const SizedBox(height: 12),
          _Card(
            icon: Icons.bar_chart_rounded,
            title: 'Активность',
            child: Row(children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.message_outlined,
                  label: 'Сообщений',
                  value: '${user.stats!.messagesCount}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  icon: Icons.group_outlined,
                  label: 'Чатов',
                  value: '${user.stats!.chatsCount}',
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 24),
        // Logout
        OutlinedButton.icon(
          onPressed: _confirmLogout,
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Выйти из аккаунта'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFEF4444),
            side: const BorderSide(color: Color(0x33EF4444)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildSocialLinks(SocialLinks links) {
    final items = <Widget>[];
    void add(String name, String? url) {
      if (url == null || url.isEmpty) return;
      items.add(InkWell(
        onTap: () => launchUrl(
            Uri.parse(url.startsWith('http') ? url : 'https://$url'),
            mode: LaunchMode.externalApplication),
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: url));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Ссылка скопирована'),
            duration: Duration(seconds: 1),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Text('$name: ',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 15)),
            Expanded(
              child: Text(url,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 15,
                      decoration: TextDecoration.underline)),
            ),
            const Icon(Icons.open_in_new,
                size: 14, color: AppColors.primary),
          ]),
        ),
      ));
    }

    add('Telegram', links.telegram);
    add('VK', links.vk);
    add('GitHub', links.github);
    add('Сайт', links.website);

    if (items.isEmpty) {
      return Text('Пользователь не добавил ссылки.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4)));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: items);
  }

  // ─── Avatar pick + edit ──────────────────────────────────────────────────
  Future<void> _pickAvatar() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null || !mounted) return;
    setState(() => _uploadingAvatar = true);
    final result = await _api.uploadFile(File(picked.path), 'image/jpeg');
    if (!mounted) return;
    if (result != null && result['url'] != null) {
      final updated =
          await _api.updateProfile(avatarUrl: result['url'] as String);
      if (mounted && updated != null) setState(() => _user = updated);
    }
    setState(() => _uploadingAvatar = false);
  }

  void _editProfile() {
    final user = _user!;
    final nameCtrl = TextEditingController(text: user.displayName);
    final bioCtrl = TextEditingController(text: user.bio ?? '');
    final statusCtrl = TextEditingController(text: user.status ?? '');
    final tgCtrl =
        TextEditingController(text: user.socialLinks?.telegram ?? '');
    final vkCtrl = TextEditingController(text: user.socialLinks?.vk ?? '');
    final ghCtrl =
        TextEditingController(text: user.socialLinks?.github ?? '');
    final siteCtrl =
        TextEditingController(text: user.socialLinks?.website ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF18181B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                const Text('Редактировать профиль',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close,
                      color: Colors.white.withValues(alpha: 0.5)),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ]),
              const SizedBox(height: 16),
              _SectionTitle('Основное'),
              const SizedBox(height: 10),
              _editField(nameCtrl, 'Имя', Icons.person_outline_rounded),
              const SizedBox(height: 10),
              _editField(bioCtrl, 'О себе', Icons.info_outline_rounded,
                  maxLines: 3),
              const SizedBox(height: 10),
              _editField(statusCtrl, 'Статус', Icons.circle_outlined),
              const SizedBox(height: 20),
              _SectionTitle('Соцсети и ссылки'),
              const SizedBox(height: 10),
              _editField(tgCtrl, 'Telegram', Icons.send_rounded),
              const SizedBox(height: 10),
              _editField(vkCtrl, 'VK', Icons.people_outline_rounded),
              const SizedBox(height: 10),
              _editField(ghCtrl, 'GitHub', Icons.code_rounded),
              const SizedBox(height: 10),
              _editField(siteCtrl, 'Сайт', Icons.language_rounded,
                  type: TextInputType.url),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final updated = await _api.updateProfile(
                    displayName: nameCtrl.text.trim(),
                    bio: bioCtrl.text.trim(),
                    status: statusCtrl.text.trim(),
                    socialLinks: {
                      'telegram': tgCtrl.text.trim(),
                      'vk': vkCtrl.text.trim(),
                      'github': ghCtrl.text.trim(),
                      'website': siteCtrl.text.trim(),
                    },
                  );
                  if (!mounted) return;
                  if (updated != null) setState(() => _user = updated);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Сохранить',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editField(TextEditingController ctrl, String label, IconData icon,
      {int maxLines = 1, TextInputType type = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: type,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
        prefixIcon: Icon(icon, color: AppColors.primary, size: 18),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF18181B),
        title: const Text('Выйти из аккаунта?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Сессия будет завершена. Вы сможете войти заново.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _logout();
  }

  Future<void> _logout() async {
    final userId = _user?.id ?? '';
    await _api.setOnlineStatus(false);
    await _api.clearToken();
    if (userId.isNotEmpty) disposeCallsOnLogout(userId);
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (r) => false,
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final IconData? icon;
  final String? title;
  final Widget child;
  const _Card({this.icon, this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 18,
                    color: const Color(0xFF7166D8)),
                const SizedBox(width: 8),
              ],
              Text(title!,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF71717A),
          letterSpacing: 1.2,
        ),
      );
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: const Color(0xFF7166D8)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.5))),
          ]),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ],
      ),
    );
  }
}
