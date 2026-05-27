import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../main.dart' show AppColors;
import 'profile_edit_screen.dart';
import 'change_password_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _s;
  User? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _api.getSettings(),
      _api.getProfile(),
    ]);
    if (!mounted) return;
    setState(() {
      _s = results[0] as Map<String, dynamic>?;
      _user = results[1] as User?;
      _loading = false;
    });
  }

  Future<void> _update(Map<String, dynamic> patch) async {
    setState(() => _s = {...?_s, ...patch});
    await _api.updateSettings(patch);
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
        title: const Text('Настройки',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _s == null
              ? const Center(child: Text('Ошибка загрузки'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    // Profile card
                    if (_user != null) _ProfileCard(
                      user: _user!,
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const ProfileEditScreen(),
                        ));
                        _load();
                      },
                    ),
                    const SizedBox(height: 28),

                    // Privacy
                    const _Group('Приватность'),
                    _Toggle(
                      icon: Icons.visibility_outlined,
                      title: 'Показывать онлайн-статус',
                      value: _s!['showOnlineStatus'] ?? true,
                      onChanged: (v) => _update({'showOnlineStatus': v}),
                    ),
                    _Toggle(
                      icon: Icons.access_time_rounded,
                      title: 'Время последнего визита',
                      value: _s!['showLastSeen'] ?? true,
                      onChanged: (v) => _update({'showLastSeen': v}),
                    ),
                    _Toggle(
                      icon: Icons.done_all_rounded,
                      title: 'Уведомления о прочтении',
                      value: _s!['readReceipts'] ?? true,
                      onChanged: (v) => _update({'readReceipts': v}),
                    ),

                    const SizedBox(height: 24),

                    // Notifications
                    const _Group('Уведомления'),
                    _Toggle(
                      icon: Icons.notifications_outlined,
                      title: 'Push-уведомления',
                      value: _s!['pushNotifications'] ?? true,
                      onChanged: (v) => _update({'pushNotifications': v}),
                    ),
                    _Toggle(
                      icon: Icons.volume_up_outlined,
                      title: 'Звук',
                      value: _s!['soundNotifications'] ?? true,
                      onChanged: (v) => _update({'soundNotifications': v}),
                    ),
                    _Toggle(
                      icon: Icons.vibration_rounded,
                      title: 'Вибрация',
                      value: _s!['vibration'] ?? true,
                      onChanged: (v) => _update({'vibration': v}),
                    ),

                    const SizedBox(height: 24),

                    // Appearance
                    const _Group('Внешний вид'),
                    _ThemeRow(
                      value: _s!['theme'] ?? 'system',
                      onChanged: (v) => _update({'theme': v}),
                    ),

                    const SizedBox(height: 24),

                    // Security
                    const _Group('Безопасность'),
                    _SecurityCard(
                      onTap: () => showDialog(
                        context: context,
                        barrierColor: Colors.black.withValues(alpha: 0.7),
                        builder: (_) => const ChangePasswordDialog(),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Danger zone
                    const _Group('Опасная зона'),
                    _DangerRow(
                      icon: Icons.delete_outline_rounded,
                      title: 'Удалить аккаунт',
                      subtitle: 'Все данные будут удалены без восстановления',
                      onTap: () {},
                    ),
                  ],
                ),
    );
  }
}

// ─── Building blocks ─────────────────────────────────────────────────────────

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

class _ProfileCard extends StatelessWidget {
  final User user;
  final VoidCallback onTap;
  const _ProfileCard({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            // Avatar
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceAlt,
              ),
              child: ClipOval(
                child: user.avatarUrl != null
                    ? Image.network(user.avatarUrl!, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _avatarFallback(user.displayName))
                    : _avatarFallback(user.displayName),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(user.status?.isNotEmpty == true ? user.status! : '@${user.username}',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.5)),
                    overflow: TextOverflow.ellipsis),
              ],
            )),
            Icon(Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.3)),
          ]),
        ),
      ),
    );
  }

  Widget _avatarFallback(String name) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      color: AppColors.primary.withValues(alpha: 0.2),
      alignment: Alignment.center,
      child: Text(letter,
          style: const TextStyle(
              fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.primary)),
    );
  }
}

class _Toggle extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Toggle({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(children: [
        Icon(icon, size: 20,
            color: value ? AppColors.primary : Colors.white.withValues(alpha: 0.4)),
        const SizedBox(width: 14),
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  fontSize: 14.5, color: Colors.white, fontWeight: FontWeight.w400)),
        ),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.primary,
          inactiveThumbColor: Colors.white.withValues(alpha: 0.6),
          inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
        ),
      ]),
    ),
  );
}

class _ThemeRow extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _ThemeRow({required this.value, required this.onChanged});

  static const _options = [
    {'v': 'light',  'l': 'Светлая',   'i': Icons.wb_sunny_outlined},
    {'v': 'dark',   'l': 'Тёмная',    'i': Icons.nightlight_outlined},
    {'v': 'system', 'l': 'Системная', 'i': Icons.phone_iphone_rounded},
  ];

  @override
  Widget build(BuildContext context) {
    return Row(children: _options.map((o) {
      final v = o['v'] as String;
      final selected = value == v;
      return Expanded(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: selected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () => onChanged(v),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: selected
                    ? Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 1)
                    : null,
              ),
              child: Column(children: [
                Icon(o['i'] as IconData, size: 22,
                    color: selected ? AppColors.primary : Colors.white.withValues(alpha: 0.5)),
                const SizedBox(height: 6),
                Text(o['l'] as String,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: selected ? Colors.white : Colors.white.withValues(alpha: 0.6))),
              ]),
            ),
          ),
        ),
      ));
    }).toList());
  }
}

class _SecurityCard extends StatelessWidget {
  final VoidCallback onTap;
  const _SecurityCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Image.asset('assets/3dlock.png', width: 56, height: 56),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Сменить пароль',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white)),
                const SizedBox(height: 3),
                Text('Через push или email',
                    style: TextStyle(
                        fontSize: 12.5, color: Colors.white.withValues(alpha: 0.5))),
              ],
            )),
            Icon(Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.3)),
          ]),
        ),
      ),
    );
  }
}

class _DangerRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _DangerRow({
    required this.icon, required this.title,
    required this.subtitle, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(children: [
          Icon(icon, size: 20, color: const Color(0xFFEF4444)),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w500,
                      color: Color(0xFFEF4444))),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 12, color: Colors.white.withValues(alpha: 0.4))),
            ],
          )),
          Icon(Icons.chevron_right_rounded,
              color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
        ]),
      ),
    );
  }
}
