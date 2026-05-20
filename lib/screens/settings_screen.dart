import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../main.dart' show AppColors;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _s;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await _api.getSettings();
    if (mounted) setState(() { _s = s; _loading = false; });
  }

  Future<void> _update(Map<String, dynamic> patch) async {
    setState(() => _s = {...?_s, ...patch});
    await _api.updateSettings(patch);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _s == null
              ? const Center(child: Text('Ошибка загрузки'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _Section('Приватность'),
                    _Card(children: [
                      _Toggle(
                        icon: Icons.visibility_outlined,
                        title: 'Показывать онлайн-статус',
                        value: _s!['showOnlineStatus'] ?? true,
                        onChanged: (v) => _update({'showOnlineStatus': v}),
                      ),
                      _Divider(),
                      _Toggle(
                        icon: Icons.access_time_rounded,
                        title: 'Показывать время последнего визита',
                        value: _s!['showLastSeen'] ?? true,
                        onChanged: (v) => _update({'showLastSeen': v}),
                      ),
                      _Divider(),
                      _Toggle(
                        icon: Icons.done_all_rounded,
                        title: 'Уведомления о прочтении',
                        value: _s!['readReceipts'] ?? true,
                        onChanged: (v) => _update({'readReceipts': v}),
                      ),
                    ]),
                    _Section('Уведомления'),
                    _Card(children: [
                      _Toggle(
                        icon: Icons.notifications_outlined,
                        title: 'Push-уведомления',
                        value: _s!['pushNotifications'] ?? true,
                        onChanged: (v) => _update({'pushNotifications': v}),
                      ),
                      _Divider(),
                      _Toggle(
                        icon: Icons.volume_up_outlined,
                        title: 'Звук уведомлений',
                        value: _s!['soundNotifications'] ?? true,
                        onChanged: (v) => _update({'soundNotifications': v}),
                      ),
                      _Divider(),
                      _Toggle(
                        icon: Icons.vibration_rounded,
                        title: 'Вибрация',
                        value: _s!['vibration'] ?? true,
                        onChanged: (v) => _update({'vibration': v}),
                      ),
                    ]),
                    _Section('Внешний вид'),
                    _Card(children: [
                      _ThemeTile(
                        value: _s!['theme'] ?? 'system',
                        onChanged: (v) => _update({'theme': v}),
                      ),
                    ]),
                    const SizedBox(height: 32),
                  ],
                ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(title.toUpperCase(),
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: AppColors.muted, letterSpacing: 1.2)),
  );
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(children: children),
  );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Divider(
      height: 1, thickness: 1, color: AppColors.border,
      indent: 52, endIndent: 0);
}

class _Toggle extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Toggle({required this.icon, required this.title,
      required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => SwitchListTile(
    secondary: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: AppColors.primary),
    ),
    title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
    value: value,
    onChanged: onChanged,
    activeColor: AppColors.primary,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  );
}

class _ThemeTile extends StatelessWidget {
  final String value;
  final ValueChanged<String?> onChanged;
  const _ThemeTile({required this.value, required this.onChanged});

  static const _labels = {'light': 'Светлая', 'dark': 'Тёмная', 'system': 'Системная'};

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.palette_outlined, size: 18, color: AppColors.primary),
    ),
    title: const Text('Тема', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
    trailing: DropdownButton<String>(
      value: value,
      underline: const SizedBox(),
      dropdownColor: AppColors.surfaceAlt,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      items: _labels.entries.map((e) =>
          DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
      onChanged: onChanged,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  );
}
