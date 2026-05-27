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
  final Set<String> _selectedIds = {};
  final List<Map<String, dynamic>> _selectedUsers = [];
  bool _searching = false;
  bool _loading = false;
  late String _access;

  final List<Map<String, String>> _serverChannels = [
    {'name': 'общий', 'type': 'TEXT'},
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
    final id = user['id'] as String;
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        _selectedUsers.removeWhere((u) => u['id'] == id);
      } else {
        _selectedIds.add(id);
        _selectedUsers.add(user);
      }
    });
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите название')));
      return;
    }
    setState(() => _loading = true);
    final userIds = _selectedUsers.map((u) => u['id'] as String).toList();

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

  void _addChannel() {
    final ctrl = TextEditingController();
    String selectedType = 'TEXT';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20, right: 20, top: 20),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Новый подканал',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 16),
            _Field(controller: ctrl, hint: 'Название', autofocus: true),
            const SizedBox(height: 16),
            const _SectionLabel('Тип'),
            const SizedBox(height: 8),
            Row(children: [
              _TypeChip(label: 'Чат', icon: Icons.tag_rounded,
                  selected: selectedType == 'TEXT',
                  onTap: () => setModal(() => selectedType = 'TEXT')),
              const SizedBox(width: 8),
              _TypeChip(label: 'Канал', icon: Icons.campaign_rounded,
                  selected: selectedType == 'CHANNEL',
                  onTap: () => setModal(() => selectedType = 'CHANNEL')),
            ]),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final n = ctrl.text.trim();
                  if (n.isNotEmpty) setState(() => _serverChannels.add({'name': n, 'type': selectedType}));
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Добавить', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  Color get _accentColor =>
      widget.type == CreateType.server ? const Color(0xFFF97316) : AppColors.primary;

  IconData get _typeIcon => switch (widget.type) {
    CreateType.group => Icons.people_rounded,
    CreateType.channel => Icons.campaign_rounded,
    CreateType.server => Icons.shield_rounded,
  };

  String get _title => switch (widget.type) {
    CreateType.group => 'Создать группу',
    CreateType.channel => 'Создать канал',
    CreateType.server => 'Создать сервер',
  };

  String get _hint => switch (widget.type) {
    CreateType.group => 'Название группы',
    CreateType.channel => 'Название канала',
    CreateType.server => 'Мой крутой сервер',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
            child: Row(children: [
              Icon(_typeIcon, color: _accentColor, size: 28),
              const SizedBox(width: 10),
              Expanded(child: Text(_title,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.3)),
              ),
            ]),
          ),

          // Content
          Expanded(child: ListView(padding: const EdgeInsets.all(20), children: [
            // Avatar upload
            Center(child: GestureDetector(
              onTap: () {}, // TODO: image picker
              child: Container(
                width: 96, height: 96,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.camera_alt_rounded, size: 28,
                      color: Colors.white.withValues(alpha: 0.2)),
                  const SizedBox(height: 4),
                  Text('ЗАГРУЗИТЬ', style: TextStyle(fontSize: 9,
                      fontWeight: FontWeight.w800, color: Colors.white.withValues(alpha: 0.2),
                      letterSpacing: 0.5)),
                ]),
              ),
            )),
            const SizedBox(height: 24),

            // Name field
            const _SectionLabel('Название'),
            const SizedBox(height: 8),
            _Field(controller: _nameCtrl, hint: _hint),
            const SizedBox(height: 20),

            // Access
            const _SectionLabel('Доступ'),
            const SizedBox(height: 8),
            Row(children: [
              _AccessChip(label: 'Публичный', icon: Icons.public_rounded,
                  selected: _access == 'PUBLIC',
                  onTap: () => setState(() => _access = 'PUBLIC')),
              const SizedBox(width: 8),
              _AccessChip(label: 'По ссылке', icon: Icons.link_rounded,
                  selected: _access == 'LINK_ONLY',
                  onTap: () => setState(() => _access = 'LINK_ONLY')),
              const SizedBox(width: 8),
              _AccessChip(label: 'Приватный', icon: Icons.lock_outline_rounded,
                  selected: _access == 'PRIVATE',
                  onTap: () => setState(() => _access = 'PRIVATE')),
            ]),
            const SizedBox(height: 8),
            _AccessDescription(access: _access),

            // Server channels
            if (widget.type == CreateType.server) ...[
              const SizedBox(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const _SectionLabel('Подканалы'),
                GestureDetector(
                  onTap: _addChannel,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add, size: 14, color: AppColors.primary),
                      SizedBox(width: 4),
                      Text('Добавить', style: TextStyle(
                          fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              ..._serverChannels.asMap().entries.map((e) => _ChannelRow(
                channel: e.value,
                onDelete: _serverChannels.length > 1
                    ? () => setState(() => _serverChannels.removeAt(e.key))
                    : null,
                onToggleType: () => setState(() {
                  _serverChannels[e.key]['type'] =
                      _serverChannels[e.key]['type'] == 'TEXT' ? 'CHANNEL' : 'TEXT';
                }),
              )),
            ],

            // Members
            const SizedBox(height: 24),
            const _SectionLabel('Добавить участников'),
            const SizedBox(height: 8),
            _Field(
              controller: _searchCtrl,
              hint: 'Поиск пользователей...',
              onChanged: _searchUsers,
              prefix: const Icon(Icons.search, size: 18, color: AppColors.muted),
              suffix: _searching
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                  : null,
            ),

            // Selected chips
            if (_selectedUsers.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: _selectedUsers.map((u) {
                return Container(
                  padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(u['displayName'] ?? u['username'] ?? '',
                        style: const TextStyle(fontSize: 12, color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => _toggleUser(u),
                      child: const Icon(Icons.close_rounded, size: 14, color: AppColors.primary),
                    ),
                  ]),
                );
              }).toList()),
            ],

            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(children: _searchResults.asMap().entries.map((e) {
                  final u = e.value;
                  final sel = _selectedIds.contains(u['id'] as String);
                  final isLast = e.key == _searchResults.length - 1;
                  return Column(children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: u['avatarUrl'] != null
                          ? CircleAvatar(backgroundImage: NetworkImage(u['avatarUrl']), radius: 20)
                          : CircleAvatar(radius: 20, backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                              child: Text((u['username'] as String? ?? '?')[0].toUpperCase(),
                                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700))),
                      title: Text(u['displayName'] ?? u['username'] ?? '',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text('@${u['username']}',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      trailing: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 26, height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: sel ? AppColors.primary : Colors.transparent,
                          border: Border.all(
                              color: sel ? AppColors.primary : AppColors.border, width: 2),
                        ),
                        child: sel
                            ? const Icon(Icons.check, size: 14, color: Colors.white)
                            : null,
                      ),
                      onTap: () => _toggleUser(u),
                    ),
                    if (!isLast) Divider(height: 1,
                        color: Colors.white.withValues(alpha: 0.05), indent: 56, endIndent: 16),
                  ]);
                }).toList()),
              ),
            ],

            const SizedBox(height: 32),
          ])),

          // Bottom button + decorative bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _create,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: widget.type == CreateType.server ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  elevation: 4,
                  shadowColor: _accentColor.withValues(alpha: 0.3),
                ),
                child: _loading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('Создать сейчас',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          // Decorative bar
          Container(
            height: 4,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: _accentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Виджеты ─────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: AppColors.muted, letterSpacing: 1));
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final Widget? prefix;
  final Widget? suffix;
  final bool autofocus;
  const _Field({required this.controller, required this.hint,
      this.onChanged, this.prefix, this.suffix, this.autofocus = false});
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    autofocus: autofocus,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: prefix,
      suffixIcon: suffix != null
          ? Padding(padding: const EdgeInsets.all(12), child: suffix) : null,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    ),
  );
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
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppColors.primary : Colors.white.withValues(alpha: 0.1),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: selected ? AppColors.primary : AppColors.muted),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
            color: selected ? AppColors.primary : AppColors.muted)),
      ]),
    ),
  );
}

class _AccessDescription extends StatelessWidget {
  final String access;
  const _AccessDescription({required this.access});
  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = switch (access) {
      'PUBLIC' => (Icons.public_rounded, 'Любой может найти и вступить', const Color(0xFF22C55E)),
      'LINK_ONLY' => (Icons.link_rounded, 'Вступить можно только по ссылке-приглашению', const Color(0xFFF59E0B)),
      _ => (Icons.lock_outline_rounded, 'Только приглашённые участники', const Color(0xFFEF4444)),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.9)))),
      ]),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  final Map<String, String> channel;
  final VoidCallback? onDelete;
  final VoidCallback onToggleType;
  const _ChannelRow({required this.channel, this.onDelete, required this.onToggleType});

  @override
  Widget build(BuildContext context) {
    final isChannel = channel['type'] == 'CHANNEL';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(children: [
          Icon(isChannel ? Icons.campaign_rounded : Icons.tag_rounded,
              size: 16, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(channel['name'] ?? '',
              style: const TextStyle(fontSize: 14, color: Colors.white))),
          GestureDetector(
            onTap: onToggleType,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(isChannel ? 'Канал' : 'Чат',
                  style: const TextStyle(fontSize: 11, color: AppColors.primary,
                      fontWeight: FontWeight.w600)),
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDelete,
              child: Icon(Icons.close_rounded, size: 16,
                  color: Colors.white.withValues(alpha: 0.3)),
            ),
          ],
        ]),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _TypeChip({required this.label, required this.icon,
      required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppColors.primary : Colors.white.withValues(alpha: 0.1),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: selected ? AppColors.primary : AppColors.muted),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
            color: selected ? AppColors.primary : AppColors.muted)),
      ]),
    ),
  );
}
