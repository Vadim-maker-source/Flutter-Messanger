import 'package:flutter/material.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _settings;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final s = await _api.getSettings();
    setState(() {
      _settings = s;
      _isLoading = false;
    });
  }

  Future<void> _update(Map<String, dynamic> patch) async {
    setState(() => _settings = {...?_settings, ...patch});
    await _api.updateSettings(patch);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _settings == null
              ? const Center(child: Text('Ошибка загрузки'))
              : ListView(
                  children: [
                    const _SectionHeader('Приватность'),
                    SwitchListTile(
                      title: const Text('Показывать онлайн-статус'),
                      value: _settings!['showOnlineStatus'] ?? true,
                      onChanged: (v) => _update({'showOnlineStatus': v}),
                    ),
                    SwitchListTile(
                      title: const Text('Показывать время последнего визита'),
                      value: _settings!['showLastSeen'] ?? true,
                      onChanged: (v) => _update({'showLastSeen': v}),
                    ),
                    const _SectionHeader('Уведомления'),
                    SwitchListTile(
                      title: const Text('Push-уведомления'),
                      value: _settings!['pushNotifications'] ?? true,
                      onChanged: (v) => _update({'pushNotifications': v}),
                    ),
                    SwitchListTile(
                      title: const Text('Звук уведомлений'),
                      value: _settings!['soundNotifications'] ?? true,
                      onChanged: (v) => _update({'soundNotifications': v}),
                    ),
                    const _SectionHeader('Внешний вид'),
                    ListTile(
                      title: const Text('Тема'),
                      trailing: DropdownButton<String>(
                        value: _settings!['theme'] ?? 'system',
                        items: const [
                          DropdownMenuItem(value: 'light', child: Text('Светлая')),
                          DropdownMenuItem(value: 'dark', child: Text('Тёмная')),
                          DropdownMenuItem(value: 'system', child: Text('Системная')),
                        ],
                        onChanged: (v) => _update({'theme': v}),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title,
          style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold)),
    );
  }
}
