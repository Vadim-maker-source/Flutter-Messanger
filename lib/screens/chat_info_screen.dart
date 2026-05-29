import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../models/chat.dart';
import '../services/api_service.dart';
import '../widgets/colored_avatar.dart';
import 'chat_screen.dart';
import 'add_member_sheet.dart';

/// Настройки сервера/группы/канала — портирован 1-в-1 из веб-версии
/// (components/ServerSettings.tsx и components/ChatSettinds.tsx).
///
/// Содержит: аватар + редактирование, инфо-карточки, быстрые действия,
/// инвайты, список каналов с удалением, список участников с поиском,
/// опасную зону (покинуть/удалить).
class ChatInfoScreen extends StatefulWidget {
  final Chat chat;
  const ChatInfoScreen({super.key, required this.chat});

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _data;
  List<dynamic> _members = [];
  List<dynamic> _channels = [];
  List<dynamic> _invites = [];
  bool _loading = true;
  bool _isAdmin = false;
  bool _isServer = false;
  bool _isEditing = false;
  bool _isSaving = false;
  String _editedName = '';
  String _search = '';
  File? _newImage;
  String? _ownerId;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    debugPrint('[ChatInfo] loading details for id=${widget.chat.id}');
    final res = await _api.getChatDetails(widget.chat.id);
    debugPrint('[ChatInfo] response: ${res?.keys.toList()}');
    if (res != null && mounted) {
      setState(() {
        _data = res;
        _members = (res['members'] as List?) ?? [];
        _channels = (res['chats'] as List?) ?? [];
        _invites = (res['invites'] as List?) ?? [];
        _isServer = res['type'] == 'SERVER';
        _isAdmin = res['isAdmin'] == true;
        _ownerId = res['ownerId'] as String?;
        _editedName = res['name'] as String? ?? widget.chat.title;
        _loading = false;
      });
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _name => _data?['name'] as String? ?? widget.chat.title;
  String? get _imageUrl => _data?['imageUrl'] as String? ?? widget.chat.imageUrl;
  int get _membersCount => (_data?['_count']?['members'] as int?) ?? _members.length;
  int get _channelsCount => (_data?['_count']?['chats'] as int?) ?? _channels.length;
  String get _access => _data?['access'] as String? ?? 'PUBLIC';
  String? get _createdAt => _data?['createdAt'] as String?;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0C),
        appBar: AppBar(backgroundColor: const Color(0xFF121214), elevation: 0),
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121214),
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_isServer ? 'Управление сервером' : 'Настройки чата',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          Text('$_membersCount участников • $_channelsCount каналов',
              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
        ]),
        actions: [
          if (_isAdmin)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white60),
              color: const Color(0xFF1A1A1F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onSelected: (v) {
                if (v == 'edit') setState(() => _isEditing = true);
                if (v == 'channel') _showCreateChannelDialog();
                if (v == 'delete') _showDeleteDialog();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Row(children: [
                  Icon(Icons.edit_outlined, size: 18, color: Colors.blue), SizedBox(width: 10), Text('Редактировать'),
                ])),
                if (_isServer)
                  const PopupMenuItem(value: 'channel', child: Row(children: [
                    Icon(Icons.tag, size: 18, color: Colors.green), SizedBox(width: 10), Text('Добавить канал'),
                  ])),
                const PopupMenuItem(value: 'delete', child: Row(children: [
                  Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 10),
                  Text('Удалить', style: TextStyle(color: Colors.red)),
                ])),
              ],
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _buildHeaderCard(),
        const SizedBox(height: 12),
        if (_isAdmin) _buildQuickActions(),
        if (_isAdmin) const SizedBox(height: 12),
        _buildInfoCards(),
        const SizedBox(height: 12),
        if (_invites.isNotEmpty) ...[ _buildInvitesCard(), const SizedBox(height: 12) ],
        if (_channels.isNotEmpty) ...[ _buildChannelsCard(), const SizedBox(height: 12) ],
        if (_members.isNotEmpty) ...[ _buildMembersCard(), const SizedBox(height: 12) ],
        _buildDangerZone(),
        const SizedBox(height: 40),
      ]),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF121214).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(children: [
        // Avatar
        Stack(children: [
          Container(
            width: 128, height: 128,
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
              child: _newImage != null
                  ? Image.file(_newImage!, fit: BoxFit.cover)
                  : _imageUrl != null
                      ? (_imageUrl!.startsWith('#')
                          // hex-цвет из БД (см. lib/avatar.ts) — рисуем заливку с буквой
                          ? ColoredAvatar(imageUrl: _imageUrl, title: _name, size: 128)
                          : Image.network(_imageUrl!, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _avatarPlaceholder()))
                      : _avatarPlaceholder(),
            ),
          ),
          if (_isEditing && _isAdmin)
            Positioned(bottom: 0, right: 0,
              child: GestureDetector(
                onTap: _pickImage,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 24),
        if (_isEditing && _isAdmin)
          Column(children: [
            TextField(
              controller: TextEditingController(text: _editedName)..selection = TextSelection.collapsed(offset: _editedName.length),
              onChanged: (v) => _editedName = v,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              decoration: InputDecoration(
                filled: true, fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: ElevatedButton(
                onPressed: _isSaving ? null : () => setState(() {
                  _isEditing = false; _editedName = _name; _newImage = null;
                }),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Отмена', style: TextStyle(color: Colors.white)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: _isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save, size: 16),
                label: Text(_isSaving ? 'Сохранение...' : 'Сохранить'),
              )),
            ]),
          ])
        else
          Column(children: [
            Text(_name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            Text(
              '$_membersCount участников${_isServer ? " • $_channelsCount каналов" : ""}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
            ),
          ]),
      ]),
    );
  }

  Widget _avatarPlaceholder() => Center(child: Text(
    _name.isNotEmpty ? _name[0].toUpperCase() : 'S',
    style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: Colors.white70),
  ));

  // ─── Quick Actions ─────────────────────────────────────────────────────────
  Widget _buildQuickActions() {
    return Row(children: [
      Expanded(child: _quickAction(Icons.person_add_outlined, 'Добавить', AppColors.primary, _openAddMember)),
      const SizedBox(width: 8),
      if (_isServer)
        Expanded(child: _quickAction(Icons.tag, 'Канал', Colors.blue, _showCreateChannelDialog)),
      if (_isServer) const SizedBox(width: 8),
      Expanded(child: _quickAction(Icons.settings_outlined, 'Настройки', Colors.orange, () => setState(() => _isEditing = true))),
    ]);
  }

  Widget _quickAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF121214).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2), shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
        ]),
      ),
    );
  }

  // ─── Info Cards ────────────────────────────────────────────────────────────
  Widget _buildInfoCards() {
    return Column(children: [
      _infoCard(
        icon: Icons.dns_outlined,
        iconColor: AppColors.primary,
        title: 'Тип',
        bigText: _isServer ? 'Сервер' : (widget.chat.type == 'CHANNEL' ? 'Канал' : 'Группа'),
        subtitle: _accessLabel(_access),
        subtitleIcon: _accessIcon(_access),
        subtitleColor: _accessColor(_access),
      ),
      const SizedBox(height: 8),
      _infoCard(
        icon: Icons.people_outline,
        iconColor: AppColors.primary,
        title: 'Участники',
        bigText: '$_membersCount',
        subtitle: '$_channelsCount каналов',
      ),
      if (_createdAt != null) ...[
        const SizedBox(height: 8),
        _infoCard(
          icon: Icons.calendar_today_outlined,
          iconColor: Colors.blue,
          title: 'Создан',
          bigText: _fmtDate(_createdAt!),
          subtitle: _fmtTime(_createdAt!),
        ),
      ],
    ]);
  }

  Widget _infoCard({required IconData icon, required Color iconColor, required String title,
      required String bigText, String? subtitle, IconData? subtitleIcon, Color? subtitleColor}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121214).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        ]),
        const SizedBox(height: 12),
        Text(bigText, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            if (subtitleIcon != null) ...[
              Icon(subtitleIcon, size: 14, color: subtitleColor ?? Colors.white60),
              const SizedBox(width: 6),
            ],
            Text(subtitle, style: TextStyle(fontSize: 13, color: subtitleColor ?? Colors.white.withValues(alpha: 0.6))),
          ]),
        ],
      ]),
    );
  }

  // ─── Invites ───────────────────────────────────────────────────────────────
  Widget _buildInvitesCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121214).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Приглашения', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 4),
        Text('Приглашайте людей в ${_isServer ? "сервер" : "чат"}',
            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4))),
        const SizedBox(height: 12),
        for (final inv in _invites) _buildInviteTile(inv),
      ]),
    );
  }

  Widget _buildInviteTile(dynamic inv) {
    final code = inv['code'] ?? '';
    final link = 'http://194.87.201.226/invite/$code';
    final uses = inv['uses'] ?? 0;
    final maxUses = inv['maxUses'] ?? 0;
    final createdAt = inv['createdAt'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.calendar_today, size: 12, color: Colors.white.withValues(alpha: 0.4)),
          const SizedBox(width: 4),
          Text('Создана: ${createdAt != null ? _fmtDate(createdAt) : "—"}',
              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
          const SizedBox(width: 12),
          Icon(Icons.timer_outlined, size: 12, color: Colors.white.withValues(alpha: 0.4)),
          const SizedBox(width: 4),
          Text('Использовано: $uses${maxUses > 0 ? "/$maxUses" : ""}',
              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
          const Spacer(),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: link));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Скопировано'), duration: Duration(seconds: 1)));
            },
            child: const Icon(Icons.copy, size: 16, color: Colors.white60),
          ),
          if (_isAdmin) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () {},
              child: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(link, style: const TextStyle(fontSize: 12, color: Colors.white)),
        ),
      ]),
    );
  }

  // ─── Channels ──────────────────────────────────────────────────────────────
  Widget _buildChannelsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121214).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: const Icon(Icons.tag, size: 18, color: Colors.blue),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Каналы', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
            Text('${_channels.length} каналов',
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
          ])),
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.add, color: AppColors.primary, size: 20),
              onPressed: _showCreateChannelDialog,
            ),
        ]),
        const SizedBox(height: 12),
        for (final ch in _channels) _buildChannelTile(ch),
      ]),
    );
  }

  Widget _buildChannelTile(dynamic ch) {
    final isChannel = ch['type'] == 'CHANNEL';
    final color = isChannel ? Colors.blue : Colors.green;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(isChannel ? Icons.tag : Icons.chat_bubble_outline, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(child: GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChatScreen(chat: Chat(
              id: ch['id'] ?? '', title: ch['name'] ?? '', type: ch['type'] ?? 'GROUP',
            )),
          )),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ch['name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            Text(isChannel ? 'Канал' : 'Группа',
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
          ]),
        )),
        if (_isAdmin)
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            onPressed: () => _confirmDeleteChannel(ch['id'] ?? '', ch['name'] ?? ''),
          ),
      ]),
    );
  }

  // ─── Members ───────────────────────────────────────────────────────────────
  Widget _buildMembersCard() {
    final filtered = _search.isEmpty ? _members : _members.where((m) {
      final u = m is Map && m.containsKey('user') ? m['user'] : m;
      final name = (u?['displayName'] ?? u?['username'] ?? '').toString().toLowerCase();
      return name.contains(_search);
    }).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121214).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: const Icon(Icons.people, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Участники', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
            Text('${_members.length} участников',
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
          ])),
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.person_add_alt_1, color: AppColors.primary, size: 20),
              onPressed: _openAddMember,
            ),
        ]),
        if (_members.length > 5) ...[
          const SizedBox(height: 12),
          TextField(
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Поиск участников...',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
              prefixIcon: Icon(Icons.search, size: 18, color: Colors.white.withValues(alpha: 0.4)),
              filled: true, fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              isDense: true,
            ),
          ),
        ],
        const SizedBox(height: 12),
        for (final m in filtered) _buildMemberTile(m),
      ]),
    );
  }

  Widget _buildMemberTile(dynamic m) {
    final user = m is Map && m.containsKey('user') ? m['user'] : m;
    final id = user?['id'] as String?;
    final name = user?['displayName'] ?? user?['username'] ?? 'Пользователь';
    final username = user?['username'] as String?;
    final avatar = user?['avatarUrl'] as String?;
    final role = m is Map ? (m['role'] as String? ?? '') : '';
    final isOwner = role == 'CREATOR' || (id != null && id == _ownerId);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.primary.withValues(alpha: 0.2),
          backgroundImage: avatar != null ? NetworkImage(avatar) : null,
          child: avatar == null
              ? Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis)),
            if (isOwner) ...[
              const SizedBox(width: 6),
              const Icon(Icons.star, size: 14, color: Colors.amber),
            ],
          ]),
          if (username != null)
            Text('@$username', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
        ])),
        if (isOwner)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Владелец', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.amber)),
          ),
      ]),
    );
  }

  // ─── Danger Zone ───────────────────────────────────────────────────────────
  Widget _buildDangerZone() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121214).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Опасная зона',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.red)),
        const SizedBox(height: 12),
        _dangerButton(Icons.logout, 'Покинуть ${_isServer ? "сервер" : "чат"}', _confirmLeave),
        if (_isAdmin) ...[
          const SizedBox(height: 8),
          _dangerButton(Icons.delete_outline, 'Удалить ${_isServer ? "сервер" : "чат"}', _showDeleteDialog),
        ],
      ]),
    );
  }

  Widget _dangerButton(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(icon, size: 18, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500))),
            const Icon(Icons.chevron_right, color: Colors.red, size: 18),
          ]),
        ),
      ),
    );
  }

  // ─── Actions ───────────────────────────────────────────────────────────────
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null && mounted) setState(() => _newImage = File(picked.path));
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    String? imageUrl;
    if (_newImage != null) {
      final r = await _api.uploadFile(_newImage!, 'image/jpeg');
      imageUrl = r?['url'] as String?;
    }
    final ok = await _api.updateChat(widget.chat.id, name: _editedName, imageUrl: imageUrl);
    if (mounted) {
      setState(() {
        _isSaving = false;
        if (ok) {
          _isEditing = false;
          _newImage = null;
          if (_data != null) {
            _data!['name'] = _editedName;
            if (imageUrl != null) _data!['imageUrl'] = imageUrl;
          }
        }
      });
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _openAddMember() async {
    final existing = _members
        .map((m) => (m['userId'] ?? m['id']) as String?)
        .whereType<String>()
        .toList();
    final added = await showAddMemberSheet(
      context,
      chatId: _isServer ? null : widget.chat.id,
      serverId: _isServer ? widget.chat.id : null,
      existingMemberIds: existing,
    );
    if (added != null && added > 0) await _load();
  }

  void _showCreateChannelDialog() {
    String name = '';
    String type = 'CHANNEL';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
      return AlertDialog(
        backgroundColor: const Color(0xFF121214),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        title: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: (type == 'CHANNEL' ? Colors.blue : Colors.green).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(type == 'CHANNEL' ? Icons.tag : Icons.people,
                color: type == 'CHANNEL' ? Colors.blue : Colors.green, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('Создать ${type == "CHANNEL" ? "канал" : "чат"}',
              style: const TextStyle(color: Colors.white, fontSize: 18))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Тип', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _typeButton('Канал', Icons.tag, Colors.blue, type == 'CHANNEL',
                () => setSt(() => type = 'CHANNEL'))),
            const SizedBox(width: 8),
            Expanded(child: _typeButton('Чат', Icons.people, Colors.green, type == 'GROUP',
                () => setSt(() => type = 'GROUP'))),
          ]),
          const SizedBox(height: 16),
          const Text('Название', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            onChanged: (v) => name = v,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: type == 'CHANNEL' ? 'общий-чат' : 'Общение',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
              filled: true, fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Colors.white60))),
          ElevatedButton(
            onPressed: name.trim().isEmpty ? null : () async {
              Navigator.pop(ctx);
              final ok = await _api.createServerChannel(widget.chat.id, name: name, type: type);
              if (ok) _load();
              else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Не удалось создать канал'), backgroundColor: Colors.red));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: type == 'CHANNEL' ? Colors.blue : Colors.green,
            ),
            child: const Text('Создать'),
          ),
        ],
      );
    }));
  }

  Widget _typeButton(String label, IconData icon, Color color, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : Colors.transparent, width: 2),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  void _confirmDeleteChannel(String id, String name) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF121214),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Удалить канал?', style: TextStyle(color: Colors.white)),
      content: Text('Канал "$name" и все сообщения будут удалены.', style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Colors.white60))),
        TextButton(onPressed: () async {
          Navigator.pop(ctx);
          final ok = await _api.deleteChat(id);
          if (ok) _load();
        }, child: const Text('Удалить', style: TextStyle(color: Colors.red))),
      ],
    ));
  }

  void _confirmLeave() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF121214),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Покинуть ${_isServer ? "сервер" : "чат"}?', style: const TextStyle(color: Colors.white)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Colors.white60))),
        TextButton(onPressed: () async {
          Navigator.pop(ctx);
          final ok = await _api.leaveChatOrServer(widget.chat.id, isServer: _isServer);
          if (!mounted) return;
          if (ok) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Вы покинули ${_isServer ? "сервер" : "чат"}')));
            Navigator.pop(context); Navigator.pop(context);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Не удалось покинуть')));
          }
        }, child: const Text('Покинуть', style: TextStyle(color: Colors.red))),
      ],
    ));
  }

  void _showDeleteDialog() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF121214),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text('Удалить ${_isServer ? "сервер" : "чат"} "$_name"?',
            style: const TextStyle(color: Colors.white, fontSize: 16))),
      ]),
      content: Text(
        'Вы уверены? Все сообщения и настройки будут удалены без возможности восстановления.',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Colors.white60))),
        TextButton(onPressed: () async {
          Navigator.pop(ctx);
          if (_isServer) {
            final result = await _api.deleteServer(widget.chat.id);
            if (!mounted) return;
            if (result.success) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Сервер удалён')));
              Navigator.pop(context); Navigator.pop(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(result.error ?? 'Не удалось удалить')));
            }
          } else {
            final ok = await _api.deleteChat(widget.chat.id);
            if (!mounted) return;
            if (ok) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Чат удалён')));
              Navigator.pop(context); Navigator.pop(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Не удалось удалить')));
            }
          }
        }, child: const Text('Удалить', style: TextStyle(color: Colors.red))),
      ],
    ));
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────
  String _accessLabel(String a) => a == 'PUBLIC' ? 'Публичный' : a == 'LINK_ONLY' ? 'По ссылке' : 'Приватный';
  Color _accessColor(String a) => a == 'PUBLIC' ? Colors.green : a == 'LINK_ONLY' ? Colors.amber : Colors.red;
  IconData _accessIcon(String a) => a == 'PUBLIC' ? Icons.public : a == 'LINK_ONLY' ? Icons.link : Icons.lock;

  String _fmtDate(String d) {
    try { return DateFormat('d MMMM yyyy', 'ru').format(DateTime.parse(d)); } catch (_) { return d; }
  }
  String _fmtTime(String d) {
    try { return DateFormat('HH:mm').format(DateTime.parse(d)); } catch (_) { return ''; }
  }
}
