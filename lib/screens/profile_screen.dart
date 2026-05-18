import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/user.dart';
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final user = await _api.getProfile();
    setState(() {
      _user = user;
      _isLoading = false;
    });
  }

  void _editProfile() {
    final nameCtrl = TextEditingController(text: _user?.displayName);
    final bioCtrl = TextEditingController(text: _user?.bio);
    final statusCtrl = TextEditingController(text: _user?.status);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Редактировать профиль'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Имя')),
            TextField(controller: bioCtrl, decoration: const InputDecoration(labelText: 'О себе')),
            TextField(controller: statusCtrl, decoration: const InputDecoration(labelText: 'Статус')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final updated = await _api.updateProfile(
                displayName: nameCtrl.text,
                bio: bioCtrl.text,
                status: statusCtrl.text,
              );
              if (updated != null) setState(() => _user = updated);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    await _api.clearToken();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: [
          if (_user != null)
            IconButton(icon: const Icon(Icons.edit), onPressed: _editProfile),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _user == null
              ? const Center(child: Text('Ошибка загрузки'))
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundImage: _user!.avatarUrl != null
                            ? NetworkImage(_user!.avatarUrl!)
                            : null,
                        child: _user!.avatarUrl == null
                            ? Text(_user!.displayName.isNotEmpty ? _user!.displayName[0] : '?',
                                style: const TextStyle(fontSize: 40))
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Text(_user!.displayName,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      Text('@${_user!.username}',
                          style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text(_user!.email),
                      if (_user!.bio != null && _user!.bio!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(_user!.bio!, textAlign: TextAlign.center),
                      ],
                      if (_user!.status != null && _user!.status!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Chip(label: Text(_user!.status!)),
                      ],
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _logout,
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('Выйти'),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
