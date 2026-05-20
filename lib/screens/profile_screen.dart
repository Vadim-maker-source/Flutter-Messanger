import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
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

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  User? _user;
  bool _loading = true;
  bool _uploading = false;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final user = await _api.getProfile();
    if (mounted) setState(() { _user = user; _loading = false; });
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 85);
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
    final tgCtrl = TextEditingController(text: _user?.socialLinks?.telegram);
    final vkCtrl = TextEditingController(text: _user?.socialLinks?.vk);
    final ghCtrl = TextEditingController(text: _user?.socialLinks?.github);
    final siteCtrl = TextEditingController(text: _user?.socialLinks?.website);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Handle
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: AppColors.border,
                      borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                const Text('Редактировать профиль',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close, color: AppColors.muted),
                    onPressed: () => Navigator.pop(ctx)),
              ]),
              const SizedBox(height: 20),
              _sectionLabel('Основное'),
              const SizedBox(height: 10),
              _field(nameCtrl, 'Имя', Icons.person_outline_rounded),
              const SizedBox(height: 10),
              _field(bioCtrl, 'О себе', Icons.info_outline_rounded, maxLines: 3),
              const SizedBox(height: 10),
              _field(statusCtrl, 'Статус', Icons.circle_outlined),
              const SizedBox(height: 20),
              _sectionLabel('Соцсети и ссылки'),
              const SizedBox(height: 10),
              _field(tgCtrl, 'Telegram', Icons.send_rounded),
              const SizedBox(height: 10),
              _field(vkCtrl, 'VK', Icons.people_outline_rounded),
              const SizedBox(height: 10),
              _field(ghCtrl, 'GitHub', Icons.code_rounded),
              const SizedBox(height: 10),
              _field(siteCtrl, 'Сайт', Icons.language_rounded,
                  type: TextInputType.url),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final links = {
                    'telegram': tgCtrl.text.trim(),
                    'vk': vkCtrl.text.trim(),
                    'github': ghCtrl.text.trim(),
                    'website': siteCtrl.text.trim(),
                  };
                  final updated = await _api.updateProfile(
                    displayName: nameCtrl.text.trim(),
                    bio: bioCtrl.text.trim(),
                    status: statusCtrl.text.trim(),
                    socialLinks: links,
                  );
                  if (mounted && updated != null) setState(() => _user = updated);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Сохранить',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text.toUpperCase(),
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: AppColors.muted, letterSpacing: 1.2));

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {int maxLines = 1, TextInputType type = TextInputType.text}) =>
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: type,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
          prefixIcon: Icon(icon, color: AppColors.primary, size: 18),
          filled: true,
          fillColor: AppColors.surfaceAlt,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      );

  Future<void> _logout() async {
    final userId = _user?.id ?? '';
    await _api.clearToken();
    if (userId.isNotEmpty) disposeCallsOnLogout(userId);
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _user == null
              ? const Center(child: Text('Ошибка загрузки'))
              : NestedScrollView(
                  headerSliverBuilder: (_, __) => [
                    SliverAppBar(
                      expandedHeight: 220,
                      pinned: true,
                      backgroundColor: AppColors.surface,
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: _editProfile,
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings_outlined),
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const SettingsScreen())),
                        ),
                      ],
                      flexibleSpace: FlexibleSpaceBar(
                        background: _buildHeader(),
                      ),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _TabBarDelegate(
                        TabBar(
                          controller: _tabCtrl,
                          indicatorColor: AppColors.primary,
                          indicatorWeight: 2,
                          labelColor: AppColors.primary,
                          unselectedLabelColor: AppColors.muted,
                          labelStyle: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                          tabs: const [
                            Tab(text: 'Информация'),
                            Tab(text: 'Соцсети'),
                          ],
                        ),
                      ),
                    ),
                  ],
                  body: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _buildInfoTab(),
                      _buildLinksTab(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        // Avatar
        GestureDetector(
          onTap: _pickAvatar,
          child: Stack(alignment: Alignment.bottomRight, children: [
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.primary.withValues(alpha: 0.3),
                           AppColors.darkAccent.withValues(alpha: 0.3)],
                ),
              ),
              child: ClipOval(
                child: _uploading
                    ? const Center(child: CircularProgressIndicator(
                        color: AppColors.primary, strokeWidth: 2))
                    : _user!.avatarUrl != null
                        ? Image.network(_user!.avatarUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _avatarFallback())
                        : _avatarFallback(),
              ),
            ),
            Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                color: AppColors.primary, shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
              ),
              child: const Icon(Icons.camera_alt_rounded, size: 13, color: Colors.white),
            ),
          ]),
        ),
        const SizedBox(width: 16),
        // Name + username + email
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(_user!.displayName,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(height: 2),
            Text('@${_user!.username}',
                style: const TextStyle(fontSize: 13, color: AppColors.secondary)),
            const SizedBox(height: 2),
            Text(_user!.email,
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        )),
      ]),
    );
  }

  Widget _buildInfoTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _infoCard(Icons.alternate_email_rounded, 'Username', '@${_user!.username}'),
        const SizedBox(height: 10),
        if (_user!.bio != null && _user!.bio!.isNotEmpty) ...[
          _infoCard(Icons.info_outline_rounded, 'О себе', _user!.bio!),
          const SizedBox(height: 10),
        ],
        if (_user!.status != null && _user!.status!.isNotEmpty) ...[
          _infoCard(Icons.circle_outlined, 'Статус', _user!.status!),
          const SizedBox(height: 10),
        ],
        _infoCard(Icons.email_outlined, 'Email', _user!.email),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Выйти из аккаунта'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFEF4444),
            side: const BorderSide(color: Color(0x33EF4444)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildLinksTab() {
    final links = _user!.socialLinks;
    final hasLinks = links != null && !links.isEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!hasLinks)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(children: [
              Icon(Icons.link_off_rounded, size: 40,
                  color: AppColors.muted.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              const Text('Нет ссылок',
                  style: TextStyle(color: AppColors.muted, fontSize: 14)),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _editProfile,
                child: const Text('Добавить',
                    style: TextStyle(color: AppColors.primary)),
              ),
            ]),
          )
        else ...[
          if (links.telegram?.isNotEmpty == true)
            _linkCard(Icons.send_rounded, 'Telegram',
                links.telegram!, const Color(0xFF2AABEE)),
          if (links.vk?.isNotEmpty == true)
            _linkCard(Icons.people_outline_rounded, 'VK',
                links.vk!, const Color(0xFF4C75A3)),
          if (links.github?.isNotEmpty == true)
            _linkCard(Icons.code_rounded, 'GitHub',
                links.github!, Colors.white),
          if (links.website?.isNotEmpty == true)
            _linkCard(Icons.language_rounded, 'Сайт',
                links.website!, AppColors.secondary),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _infoCard(IconData icon, String label, String value) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: AppColors.primary),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted,
            fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 14, color: Colors.white)),
      ])),
    ]),
  );

  Widget _linkCard(IconData icon, String label, String url, Color color) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          onTap: () => launchUrl(Uri.parse(
              url.startsWith('http') ? url : 'https://$url')),
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: url));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ссылка скопирована'),
                  duration: Duration(seconds: 1)),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 12,
                    color: AppColors.muted, fontWeight: FontWeight.w500)),
                Text(url, style: TextStyle(fontSize: 13, color: color),
                    overflow: TextOverflow.ellipsis),
              ])),
              Icon(Icons.open_in_new_rounded, size: 16,
                  color: AppColors.muted.withValues(alpha: 0.5)),
            ]),
          ),
        ),
      );

  Widget _avatarFallback() => Container(
    color: AppColors.surfaceAlt,
    child: Center(child: Text(
      _user!.displayName.isNotEmpty ? _user!.displayName[0].toUpperCase() : '?',
      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white),
    )),
  );
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(color: AppColors.surface, child: tabBar);

  @override
  bool shouldRebuild(_TabBarDelegate old) => false;
}
