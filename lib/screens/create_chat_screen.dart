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
    if (q.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    final res = await _api.searchUsers(q);
    if (!mounted) return;
    setState(() {
      _searchResults = res;
      _searching = false;
    });
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

    if (!mounted) return;
    setState(() => _loading = false);
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
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF16161B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              left: 20, right: 20, top: 8),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(top: 4, bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const Text('Новый подканал',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 4),
            Text('Выберите тип и название',
                style: TextStyle(
                    fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
            const SizedBox(height: 18),
            _SoftTextField(controller: ctrl, hint: 'Название', autofocus: true),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _PickerChip(
                icon: Icons.tag_rounded, label: 'Чат',
                selected: selectedType == 'TEXT',
                onTap: () => setModal(() => selectedType = 'TEXT'))),
              const SizedBox(width: 8),
              Expanded(child: _PickerChip(
                icon: Icons.campaign_rounded, label: 'Канал',
                selected: selectedType == 'CHANNEL',
                onTap: () => setModal(() => selectedType = 'CHANNEL'))),
            ]),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final n = ctrl.text.trim();
                  if (n.isNotEmpty) {
                    setState(() => _serverChannels.add({'name': n, 'type': selectedType}));
                  }
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text('Добавить', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );
  }

  IconData get _typeIcon => switch (widget.type) {
        CreateType.group => Icons.people_alt_rounded,
        CreateType.channel => Icons.campaign_rounded,
        CreateType.server => Icons.dns_rounded,
      };

  String get _title => switch (widget.type) {
        CreateType.group => 'Новая группа',
        CreateType.channel => 'Новый канал',
        CreateType.server => 'Новый сервер',
      };

  String get _hint => switch (widget.type) {
        CreateType.group => 'Название группы',
        CreateType.channel => 'Название канала',
        CreateType.server => 'Название сервера',
      };

  String get _description => switch (widget.type) {
        CreateType.group => 'Чат для общения с участниками',
        CreateType.channel => 'Лента для подписчиков',
        CreateType.server => 'Сообщество с каналами и чатами',
      };

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
        title: Text(_title,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // Type icon header
          Center(child: Column(children: [
            Container(
              width: 76, height: 76,
              decoration: BoxDecoration(
                color: const Color(0xFF1F1F26),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(_typeIcon, size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 14),
            Text(_description,
                style: TextStyle(
                    fontSize: 13, color: Colors.white.withValues(alpha: 0.5)),
                textAlign: TextAlign.center),
          ])),
          const SizedBox(height: 28),

          // Name
          const _Group('Название'),
          _SoftTextField(controller: _nameCtrl, hint: _hint),

          const SizedBox(height: 28),

          // Access
          const _Group('Доступ'),
          _AccessSelector(
            value: _access,
            onChanged: (v) => setState(() => _access = v),
          ),

          if (widget.type == CreateType.server) ...[
            const SizedBox(height: 28),
            Row(children: [
              const Expanded(child: _Group('Подканалы')),
              GestureDetector(
                onTap: _addChannel,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, size: 14, color: AppColors.primary),
                    SizedBox(width: 4),
                    Text('Добавить',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
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

          const SizedBox(height: 28),
          const _Group('Участники'),
          _SoftTextField(
            controller: _searchCtrl,
            hint: 'Поиск пользователей',
            onChanged: _searchUsers,
            prefix: Icon(Icons.search_rounded,
                size: 18, color: Colors.white.withValues(alpha: 0.4)),
            suffix: _searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    ),
                  )
                : null,
          ),

          // Selected chips
          if (_selectedUsers.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: _selectedUsers.map((u) {
              return GestureDetector(
                onTap: () => _toggleUser(u),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(u['displayName'] ?? u['username'] ?? '',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    const Icon(Icons.close_rounded,
                        size: 14, color: AppColors.primary),
                  ]),
                ),
              );
            }).toList()),
          ],

          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1F1F26),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(children: _searchResults.asMap().entries.map((e) {
                final u = e.value;
                final sel = _selectedIds.contains(u['id'] as String);
                final isLast = e.key == _searchResults.length - 1;
                return Column(children: [
                  InkWell(
                    onTap: () => _toggleUser(u),
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(children: [
                        _UserAvatar(user: u, size: 38),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(u['displayName'] ?? u['username'] ?? '',
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white),
                                overflow: TextOverflow.ellipsis),
                            Text('@${u['username']}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.4)),
                                overflow: TextOverflow.ellipsis),
                          ],
                        )),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: sel ? AppColors.primary : Colors.transparent,
                            border: Border.all(
                                color: sel
                                    ? AppColors.primary
                                    : Colors.white.withValues(alpha: 0.2),
                                width: 1.5),
                          ),
                          child: sel
                              ? const Icon(Icons.check_rounded,
                                  size: 14, color: Colors.white)
                              : null,
                        ),
                      ]),
                    ),
                  ),
                  if (!isLast)
                    Divider(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.05),
                        indent: 64, endIndent: 14),
                ]);
              }).toList()),
            ),
          ],

          const SizedBox(height: 28),
          _PrimaryButton(
            label: switch (widget.type) {
              CreateType.group => 'Создать группу',
              CreateType.channel => 'Создать канал',
              CreateType.server => 'Создать сервер',
            },
            loading: _loading,
            onTap: _create,
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
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Text(title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.35),
              letterSpacing: 1.4,
            )),
      );
}

class _SoftTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final Widget? prefix;
  final Widget? suffix;
  final bool autofocus;

  const _SoftTextField({
    required this.controller,
    required this.hint,
    this.onChanged,
    this.prefix,
    this.suffix,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        autofocus: autofocus,
        style: const TextStyle(color: Colors.white, fontSize: 14.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14.5),
          prefixIcon: prefix,
          suffixIcon: suffix,
          filled: true,
          fillColor: const Color(0xFF1F1F26),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.4), width: 1)),
        ),
      );
}

class _AccessSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _AccessSelector({required this.value, required this.onChanged});

  static const _options = [
    {'v': 'PUBLIC',    'l': 'Публичный',  'i': Icons.public_rounded,
      'desc': 'Любой может найти и вступить', 'color': Color(0xFF22C55E)},
    {'v': 'LINK_ONLY', 'l': 'По ссылке',  'i': Icons.link_rounded,
      'desc': 'Только по ссылке-приглашению', 'color': Color(0xFFF59E0B)},
    {'v': 'PRIVATE',   'l': 'Приватный',  'i': Icons.lock_outline_rounded,
      'desc': 'Только приглашённые участники', 'color': Color(0xFFEF4444)},
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _options.map((o) {
        final v = o['v'] as String;
        final selected = value == v;
        final color = o['color'] as Color;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.1)
                : const Color(0xFF1F1F26),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: () => onChanged(v),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: selected
                      ? Border.all(
                          color: AppColors.primary.withValues(alpha: 0.5),
                          width: 1)
                      : null,
                ),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(o['i'] as IconData, size: 18, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o['l'] as String,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(o['desc'] as String,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.4))),
                    ],
                  )),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? AppColors.primary : Colors.transparent,
                      border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : Colors.white.withValues(alpha: 0.2),
                          width: 1.5),
                    ),
                    child: selected
                        ? const Icon(Icons.check_rounded,
                            size: 14, color: Colors.white)
                        : null,
                  ),
                ]),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  final Map<String, String> channel;
  final VoidCallback? onDelete;
  final VoidCallback onToggleType;
  const _ChannelRow({
    required this.channel,
    this.onDelete,
    required this.onToggleType,
  });

  @override
  Widget build(BuildContext context) {
    final isChannel = channel['type'] == 'CHANNEL';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F26),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Icon(isChannel ? Icons.campaign_rounded : Icons.tag_rounded,
              size: 17, color: Colors.white.withValues(alpha: 0.5)),
          const SizedBox(width: 10),
          Expanded(child: Text(channel['name'] ?? '',
              style: const TextStyle(fontSize: 14, color: Colors.white))),
          GestureDetector(
            onTap: onToggleType,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(isChannel ? 'Канал' : 'Чат',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600)),
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDelete,
              child: Icon(Icons.close_rounded,
                  size: 17, color: Colors.white.withValues(alpha: 0.3)),
            ),
          ],
        ]),
      ),
    );
  }
}

class _PickerChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PickerChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.15)
            : const Color(0xFF1F1F26),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: selected
                  ? Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4), width: 1)
                  : null,
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon,
                  size: 16,
                  color: selected
                      ? AppColors.primary
                      : Colors.white.withValues(alpha: 0.5)),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.6))),
            ]),
          ),
        ),
      );
}

class _UserAvatar extends StatelessWidget {
  final Map<String, dynamic> user;
  final double size;
  const _UserAvatar({required this.user, required this.size});

  @override
  Widget build(BuildContext context) {
    final url = user['avatarUrl'] as String?;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(backgroundImage: NetworkImage(url), radius: size / 2);
    }
    final letter = (user['username'] as String? ?? '?').characters.first.toUpperCase();
    return Container(
      width: size, height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withValues(alpha: 0.15),
      ),
      child: Text(letter,
          style: TextStyle(
              fontSize: size * 0.42,
              color: AppColors.primary,
              fontWeight: FontWeight.w700)),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;
  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 50,
            alignment: Alignment.center,
            child: loading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
          ),
        ),
      );
}
