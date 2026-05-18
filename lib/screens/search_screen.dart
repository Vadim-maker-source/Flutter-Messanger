import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../models/chat.dart';
import 'chat_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _api = ApiService();
  final _ctrl = TextEditingController();

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _chats = [];
  List<Map<String, dynamic>> _servers = [];
  bool _loading = false;
  bool _hasSearched = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() { _users = []; _chats = []; _servers = []; _hasSearched = false; });
      return;
    }
    setState(() => _loading = true);
    final res = await _api.search(q);
    setState(() {
      _users = res['users'] as List<Map<String, dynamic>>;
      _chats = res['chats'] as List<Map<String, dynamic>>;
      _servers = res['servers'] as List<Map<String, dynamic>>;
      _loading = false;
      _hasSearched = true;
    });
  }

  Future<void> _openPrivateChat(Map<String, dynamic> user) async {
    final chat = await _api.createPrivateChat(user['id'] as String);
    if (chat != null && mounted) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(chat: Chat.fromJson({
          'id': chat['id'],
          'title': user['displayName'] ?? user['username'],
          'imageUrl': user['avatarUrl'],
          'type': 'PRIVATE',
        })),
      ));
    }
  }

  void _openChat(Map<String, dynamic> chat) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChatScreen(chat: Chat.fromJson({
        'id': chat['id'],
        'title': chat['name'],
        'imageUrl': chat['imageUrl'],
        'type': chat['type'] ?? 'GROUP',
      })),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hasResults = _users.isNotEmpty || _chats.isNotEmpty || _servers.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          onChanged: _search,
          style: const TextStyle(fontSize: 16),
          decoration: const InputDecoration(
            hintText: 'Поиск пользователей, чатов, серверов...',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _ctrl.clear();
                _search('');
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : !_hasSearched
              ? _buildEmptyState()
              : !hasResults
                  ? _buildNoResults()
                  : ListView(children: [
                      if (_users.isNotEmpty) ...[
                        _SectionHeader('Пользователи', Icons.person_outline_rounded),
                        ..._users.map((u) => _UserTile(user: u, onTap: () => _openPrivateChat(u))),
                      ],
                      if (_chats.isNotEmpty) ...[
                        _SectionHeader('Чаты', Icons.chat_bubble_outline_rounded),
                        ..._chats.map((c) => _ChatTile(chat: c, onTap: () => _openChat(c))),
                      ],
                      if (_servers.isNotEmpty) ...[
                        _SectionHeader('Серверы', Icons.dns_rounded),
                        ..._servers.map((s) => _ServerTile(server: s)),
                      ],
                      const SizedBox(height: 40),
                    ]),
    );
  }

  Widget _buildEmptyState() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.search_rounded, size: 32, color: AppColors.primary),
      ),
      const SizedBox(height: 16),
      const Text('Начните поиск', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      const Text('Пользователи, чаты, каналы, серверы',
          style: TextStyle(fontSize: 13, color: AppColors.muted)),
    ]),
  );

  Widget _buildNoResults() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.search_off_rounded, size: 48, color: AppColors.muted),
      const SizedBox(height: 12),
      const Text('Ничего не найдено', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text('По запросу «${_ctrl.text}»',
          style: const TextStyle(fontSize: 13, color: AppColors.muted)),
    ]),
  );
}

// ─── Секция ──────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader(this.title, this.icon);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Row(children: [
      Icon(icon, size: 14, color: AppColors.muted),
      const SizedBox(width: 6),
      Text(title.toUpperCase(),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: AppColors.muted, letterSpacing: 1.2)),
    ]),
  );
}

// ─── Тайлы ───────────────────────────────────────────────────────────────────

class _UserTile extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onTap;
  const _UserTile({required this.user, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: user['avatarUrl'] != null
        ? CircleAvatar(backgroundImage: NetworkImage(user['avatarUrl']), radius: 20)
        : CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.surfaceAlt,
            child: Text((user['username'] as String? ?? '?')[0].toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w700))),
    title: Text(user['displayName'] ?? user['username'] ?? '',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
    subtitle: Text('@${user['username']}',
        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
    trailing: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text('Написать',
          style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
    ),
    onTap: onTap,
  );
}

class _ChatTile extends StatelessWidget {
  final Map<String, dynamic> chat;
  final VoidCallback onTap;
  const _ChatTile({required this.chat, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final isChannel = chat['type'] == 'CHANNEL';
    return ListTile(
      leading: chat['imageUrl'] != null
          ? CircleAvatar(backgroundImage: NetworkImage(chat['imageUrl']), radius: 20)
          : Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: isChannel
                    ? AppColors.primary.withOpacity(0.15)
                    : AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isChannel ? Icons.tag : Icons.group_rounded,
                size: 18,
                color: isChannel ? AppColors.primary : AppColors.muted,
              ),
            ),
      title: Text(chat['name'] ?? '',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: chat['lastMessage'] != null
          ? Text(chat['lastMessage'], maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.muted))
          : Text(isChannel ? 'Канал' : 'Группа',
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      onTap: onTap,
    );
  }
}

class _ServerTile extends StatelessWidget {
  final Map<String, dynamic> server;
  const _ServerTile({required this.server});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: server['imageUrl'] != null
        ? CircleAvatar(backgroundImage: NetworkImage(server['imageUrl']), radius: 20)
        : Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.darkAccent],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(
              (server['name'] as String? ?? 'S')[0].toUpperCase(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            )),
          ),
    title: Text(server['name'] ?? '',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
    subtitle: server['memberCount'] != null
        ? Text('${server['memberCount']} участников',
            style: const TextStyle(fontSize: 12, color: AppColors.muted))
        : null,
  );
}
