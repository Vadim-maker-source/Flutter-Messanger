import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../services/pusher_service_ws.dart';
import '../models/chat.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import 'create_chat_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();
  final _pusher = PusherService();
  List<Chat> _chats = [];
  List<Map<String, dynamic>> _servers = [];
  bool _isLoading = true;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _load();
    _initPusher();
  }

  Future<void> _initPusher() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('user_id');
    if (_userId == null) return;
    _pusher.subscribeToSidebar(_userId!, onUpdate: (chatId, unreadCount, lastMessage) {
      if (!mounted) return;
      setState(() {
        final i = _chats.indexWhere((c) => c.id == chatId);
        if (i != -1) {
          final c = _chats[i];
          _chats[i] = Chat(
            id: c.id, title: c.title, imageUrl: c.imageUrl, type: c.type,
            role: c.role, unreadCount: unreadCount,
            lastMessage: lastMessage?['content'] as String? ?? c.lastMessage,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    if (_userId != null) _pusher.unsubscribeFromSidebar(_userId!);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final result = await _api.getSidebar();
    setState(() {
      _chats = result['chats'] as List<Chat>;
      _servers = List<Map<String, dynamic>>.from(result['servers'] ?? []);
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: _load,
                      child: _buildList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.surfaceAlt)),
      ),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.darkAccent],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.chat_bubble_rounded, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          const Text('Чаты',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const Spacer(),
          _HBtn(icon: Icons.search_rounded, onTap: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()))
                  .then((_) => _load())),
          const SizedBox(width: 8),
          _HBtn(icon: Icons.add_rounded, onTap: _showCreateMenu),
          const SizedBox(width: 8),
          _HBtn(icon: Icons.person_outline_rounded, onTap: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()))),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_chats.isEmpty && _servers.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.chat_bubble_outline_rounded, size: 32, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          const Text('Нет чатов',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Нажмите + чтобы начать',
              style: TextStyle(fontSize: 13, color: AppColors.muted)),
        ]),
      );
    }
    return ListView(children: [
      if (_servers.isNotEmpty) ...[
        _SectionLabel('Серверы'),
        ..._servers.map(_buildServerTile),
        const SizedBox(height: 4),
      ],
      if (_chats.isNotEmpty) ...[
        _SectionLabel('Чаты'),
        ..._chats.map(_buildChatTile),
      ],
      const SizedBox(height: 80),
    ]);
  }

  Widget _buildChatTile(Chat chat) {
    final isChannel = chat.type == 'CHANNEL';
    final isGroup = chat.type == 'GROUP';
    return InkWell(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => ChatScreen(chat: chat))).then((_) => _load()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            _Avatar(imageUrl: chat.imageUrl, name: chat.title,
                isChannel: isChannel, isGroup: isGroup),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (isChannel)
                    const Padding(padding: EdgeInsets.only(right: 3),
                        child: Icon(Icons.tag, size: 13, color: AppColors.primary)),
                  Expanded(child: Text(chat.title,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      overflow: TextOverflow.ellipsis)),
                ]),
                if (chat.lastMessage != null)
                  Text(chat.lastMessage!, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            )),
            if (chat.unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${chat.unreadCount}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _buildServerTile(Map<String, dynamic> server) {
    final chats = (server['chats'] as List?) ?? [];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                    )),
                  ),
            title: Text(server['name'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text('${chats.length} каналов',
                style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            iconColor: AppColors.muted,
            collapsedIconColor: AppColors.muted,
            children: chats.map<Widget>((ch) {
              final isChannel = ch['type'] == 'CHANNEL';
              return ListTile(
                contentPadding: const EdgeInsets.only(left: 64, right: 16),
                leading: Icon(isChannel ? Icons.tag : Icons.forum_outlined,
                    size: 16, color: AppColors.muted),
                title: Text(ch['name'] ?? '', style: const TextStyle(fontSize: 13)),
                dense: true,
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ChatScreen(chat: Chat.fromJson({
                    'id': ch['id'], 'title': ch['name'], 'type': ch['type'],
                  })),
                )).then((_) => _load()),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showCreateMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
        const Padding(padding: EdgeInsets.only(bottom: 8),
            child: Text('Создать', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
        _SheetItem(icon: Icons.group_rounded, color: AppColors.primary,
            label: 'Публичная группа', subtitle: 'Открытый чат для всех',
            onTap: () { Navigator.pop(context); _goCreate(CreateType.group, access: 'PUBLIC'); }),
        _SheetItem(icon: Icons.lock_outline_rounded, color: const Color(0xFF059669),
            label: 'Приватная группа', subtitle: 'Только по приглашению',
            onTap: () { Navigator.pop(context); _goCreate(CreateType.group, access: 'PRIVATE'); }),
        _SheetItem(icon: Icons.tag_rounded, color: const Color(0xFF0EA5E9),
            label: 'Канал', subtitle: 'Пишет только создатель',
            onTap: () { Navigator.pop(context); _goCreate(CreateType.channel); }),
        _SheetItem(icon: Icons.dns_rounded, color: AppColors.darkAccent,
            label: 'Сервер', subtitle: 'Сообщество с каналами',
            onTap: () { Navigator.pop(context); _goCreate(CreateType.server); }),
        const SizedBox(height: 8),
      ])),
    );
  }

  void _goCreate(CreateType type, {String? access}) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CreateChatScreen(type: type, initialAccess: access),
    )).then((_) => _load());
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Text(title.toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            color: AppColors.muted, letterSpacing: 1.2)),
  );
}

class _HBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, size: 18, color: Colors.white),
    ),
  );
}

class _Avatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final bool isChannel;
  final bool isGroup;
  const _Avatar({required this.imageUrl, required this.name,
      this.isChannel = false, this.isGroup = false});
  @override
  Widget build(BuildContext context) {
    if (imageUrl != null) {
      return CircleAvatar(backgroundImage: NetworkImage(imageUrl!), radius: 22);
    }
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: isChannel
            ? AppColors.primary.withOpacity(0.15)
            : isGroup
                ? AppColors.darkAccent.withOpacity(0.15)
                : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: isChannel
          ? const Icon(Icons.tag, size: 20, color: AppColors.primary)
          : isGroup
              ? const Icon(Icons.group_rounded, size: 20, color: AppColors.secondary)
              : Center(child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
                )),
    );
  }
}

class _SheetItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _SheetItem({required this.icon, required this.color,
      required this.label, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: color, size: 20),
    ),
    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
    onTap: onTap,
  );
}
