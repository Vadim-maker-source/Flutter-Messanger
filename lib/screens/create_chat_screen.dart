import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api_service.dart';

enum CreateType { group, channel, server }

class CreateChatScreen extends StatefulWidget {
  final CreateType type;
  final String? initialAccess;
  const CreateChatScreen({super.key, required this.type, this.initialAccess});

  @override
  State<CreateChatScreen> createState() => _CreateChatScreenState();
}

class _CreateChatScreenState extends State<CreateChatScreen> {
  final _api = ApiService();
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _selected = [];
  bool _searching = false;
  bool _loading = false;
  late String _access;

  // Для сервера — список каналов
  final List<Map<String, String>> _serverChannels = [
    {'name': 'general', 'type': 'TEXT'},
  ];

  @override
  void initState() {
    super.initState();
    _access = widget.initialAccess ?? 'PUBLIC';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String q) async {
    if (q.trim().isEmpty) { setState(() => _searchResults = []); return; }
    setState(() => _searching = true);
    final res = await _api.searchUsers(q);
    setState(() { _searchResults = res; _searching = false; });
  }

  void _toggleUser(Map<String, dynamic> user) {
    setState(() {
      final idx = _selected.indexWhere((u) => u['id'] == user['id']);
      if (idx >= 0) _selected.removeAt(idx); else _selected.add(user);
    });
  }

  bool _isSelected(String id) => _selected.any((u) => u['id'] == id);

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите название')));
      return;
    }
    setState(() => _loading = true);
    final userIds = _selected.map((u) => u['id'] as String).toList();

    Map<String, dynamic>? result;
    switch (widget.type) {
      case CreateType.group:
        result = await _api.createGroup(name: name, userIds: userIds, access: _access);
      case CreateType.channel:
        result = await _api.createChannel(name: name, userIds: userIds, access: _access);
      case CreateType.server:
        result = await _api.createServer(
            name: name, userIds: userIds, channels: _serverChannels, access: _access);
    }

    setState(() => _loading = false);
    if (!mounted) return;
    if (result != null) {
      Navigator.pop(context, result);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка создания')));
    }
  }

  String get _title => switch (widget.type) {
    CreateType.group => 'Создать группу',
    CreateType.channel => 'Создать канал',
    CreateType.server => 'Создать сервер',
  };

  String get _hint => switch (widget.type) {
    CreateType.group => 'Название группы',
    CreateType.channel => 'Название канала',
    CreateType.server => 'Название сервера',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_loading)
            const Padding(padding: EdgeInsets.all(16),
                child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
          else
            TextButton(
              onPressed: _create,
              child: const Text('Создать',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Название
        _Label('Название'),
        const SizedBox(height: 8),
        TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(hintText: _hint),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 20),

        // Доступ (не для канала — канал всегда PUBLIC по умолчанию, но можно менять)
        _Label('Доступ'),
        const SizedBox(height: 8),
        Row(children: [
          _AccessChip(
            label: 'Публичный',
            icon: Icons.public_rounded,
            selected: _access == 'PUBLIC',
            onTap: () => setState(() => _access = 'PUBLIC'),
          ),
          const SizedBox(width: 10),
          _AccessChip(
            label: 'Приватный',
            icon: Icons.lock_outline_rounded,
            selected: _access == 'PRIVATE',
            onTap: () => setState(() => _access = 'PRIVATE'),
          ),
        ]),

        // Описание типа
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withOpacity(0.2)),
          ),
          child: Row(children: [
            Icon(_typeIcon, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(_typeDescription,
                style: const TextStyle(fontSize: 12, color: AppColors.secondary))),
          ]),
        ),

        // Каналы сервера
        if (widget.type == CreateType.server) ...[
          const SizedBox(height: 20),
          _Label('Каналы сервера'),
          const SizedBox(height: 8),
          ..._serverChannels.asMap().entries.map((e) => _ServerChannelRow(
            channel: e.value,
            onDelete: _serverChannels.length > 1
                ? () => setState(() => _serverChannels.removeAt(e.key))
                : null,
          )),
          TextButton.icon(
            onPressed: _addServerChannel,
            icon: const Icon(Icons.add, size: 16, color: AppColors.primary),
            label: const Text('Добавить канал',
                style: TextStyle(color: AppColors.primary, fontSize: 13)),
          ),
        ],

        // Участники
        const SizedBox(height: 20),
        _Label('Добавить участников'),
        const SizedBox(height: 8),
        TextField(
          controller: _searchCtrl,
          onChanged: _searchUsers,
          decoration: InputDecoration(
            hintText: 'Поиск пользователей...',
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: _searching
                ? const Padding(padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : null,
          ),
        ),

        // Выбранные
        if (_selected.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: _selected.map((u) => Chip(
            backgroundColor: AppColors.primary.withOpacity(0.15),
            label: Text(u['displayName'] ?? u['username'] ?? '',
                style: const TextStyle(fontSize: 12, color: AppColors.secondary)),
            deleteIcon: const Icon(Icons.close, size: 14, color: AppColors.muted),
            onDeleted: () => _toggleUser(u),
          )).toList()),
        ],

        // Результаты поиска
        if (_searchResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._searchResults.map((u) {
            final sel = _isSelected(u['id'] as String);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: u['avatarUrl'] != null
                  ? CircleAvatar(backgroundImage: NetworkImage(u['avatarUrl']), radius: 18)
                  : CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.surfaceAlt,
                      child: Text((u['username'] as String? ?? '?')[0].toUpperCase())),
              title: Text(u['displayName'] ?? u['username'] ?? '',
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text('@${u['username']}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              trailing: sel
                  ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                  : const Icon(Icons.add_circle_outline_rounded, color: AppColors.muted),
              onTap: () => _toggleUser(u),
            );
          }),
        ],
      ]),
    );
  }

  IconData get _typeIcon => switch (widget.type) {
    CreateType.group => Icons.group_rounded,
    CreateType.channel => Icons.tag_rounded,
    CreateType.server => Icons.dns_rounded,
  };

  String get _typeDescription => switch (widget.type) {
    CreateType.group => 'Группа — все участники могут писать сообщения.',
    CreateType.channel => 'Канал — только создатель и администраторы могут публиковать.',
    CreateType.server => 'Сервер — сообщество с несколькими каналами.',
  };

  void _addServerChannel() {
    showDialog(
      context: context,
      builder: (_) {
        final ctrl = TextEditingController();
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Новый канал'),
          content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Название')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('Отмена', style: TextStyle(color: AppColors.muted))),
            TextButton(
              onPressed: () {
                final n = ctrl.text.trim();
                if (n.isNotEmpty) setState(() => _serverChannels.add({'name': n, 'type': 'TEXT'}));
                Navigator.pop(context);
              },
              child: const Text('Добавить', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: AppColors.muted, letterSpacing: 1));
}

class _AccessChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _AccessChip({required this.label, required this.icon,
      required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary.withOpacity(0.15) : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: selected ? AppColors.primary : AppColors.muted),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600,
          color: selected ? AppColors.primary : AppColors.muted,
        )),
      ]),
    ),
  );
}

class _ServerChannelRow extends StatelessWidget {
  final Map<String, String> channel;
  final VoidCallback? onDelete;
  const _ServerChannelRow({required this.channel, this.onDelete});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        const Icon(Icons.tag, size: 16, color: AppColors.muted),
        const SizedBox(width: 8),
        Expanded(child: Text(channel['name'] ?? '',
            style: const TextStyle(fontSize: 14))),
        if (onDelete != null)
          GestureDetector(onTap: onDelete,
              child: const Icon(Icons.close, size: 16, color: AppColors.muted)),
      ]),
    ),
  );
}
