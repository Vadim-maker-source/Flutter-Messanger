import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../services/pusher_service_ws.dart';
import '../models/chat.dart';
import '../widgets/colored_avatar.dart';
import 'chat_screen.dart';
import 'server_channels_screen.dart';
import 'profile_screen.dart';
import 'create_chat_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _api = ApiService();
  final _pusher = PusherService();
  List<Chat> _chats = [];
  List<Map<String, dynamic>> _servers = [];
  bool _isLoading = true;
  String? _userId;
  Timer? _heartbeat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _initPusher();
    _api.setOnlineStatus(true);
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) => _api.setOnlineStatus(true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _api.setOnlineStatus(true);
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) => _api.setOnlineStatus(true));
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _api.setOnlineStatus(false);
      _heartbeat?.cancel();
    }
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
    _heartbeat?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _api.setOnlineStatus(false);
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
      backgroundColor: AppColors.surface,
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
      color: AppColors.surface,
      child: Column(children: [
        // Top row: logo + title + menu
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Row(children: [
            // Logo from assets
            Image.asset('assets/icon.png', width: 30, height: 30),
            const SizedBox(width: 10),
            const Text('Чаты',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            const Spacer(),
            // Three-dot menu
            IconButton(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              onPressed: _showMainMenu,
            ),
          ]),
        ),
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SearchScreen()))
                .then((_) => _load()),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.searchbar,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(children: [
                const SizedBox(width: 14),
                const Icon(Icons.search_rounded, color: AppColors.muted, size: 20),
                const SizedBox(width: 10),
                Text('Поиск чатов',
                    style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 15)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildList() {
    // Разделяем: закреплённые, обычные, архивные
    final pinned = _chats.where((c) => c.isPinned && !c.isArchived).toList();
    final normal = _chats.where((c) => !c.isPinned && !c.isArchived).toList();
    final archived = _chats.where((c) => c.isArchived).toList();

    final hasAny = _chats.isNotEmpty || _servers.isNotEmpty;

    if (!hasAny) {
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
        ..._servers.map(_buildServerTile),
      ],
      // Кнопка «Архив» — вверху (как в Telegram)
      if (archived.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: InkWell(
            onTap: () => _showArchivedChats(archived),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                const Icon(Icons.archive_outlined, color: AppColors.muted, size: 20),
                const SizedBox(width: 12),
                const Text('Архив',
                    style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${archived.length}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 14)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
              ]),
            ),
          ),
        ),
      // Закреплённые — с заголовком
      if (pinned.isNotEmpty) ...[
        const _SectionLabel('Закреплённые'),
        ...pinned.map(_buildChatTile),
      ],
      // Обычные — с заголовком если есть закреплённые
      if (normal.isNotEmpty) ...[
        if (pinned.isNotEmpty) const _SectionLabel('Все чаты'),
        ...normal.map(_buildChatTile),
      ],
      const SizedBox(height: 80),
    ]);
  }

  void _showArchivedChats(List<Chat> archived) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Column(children: [
          Container(width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Архив',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              children: archived.map(_buildChatTile).toList(),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildChatTile(Chat chat) {
    final isChannel = chat.type == 'CHANNEL';
    final isGroup = chat.type == 'GROUP';
    return InkWell(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => ChatScreen(chat: chat))).then((_) => _load()),
      onLongPress: () => _showChatContextMenu(chat),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          _Avatar(imageUrl: chat.imageUrl, name: chat.title,
              isChannel: isChannel, isGroup: isGroup, id: chat.id),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                if (isChannel)
                  const Padding(padding: EdgeInsets.only(right: 3),
                      child: Icon(Icons.tag, size: 13, color: AppColors.primary)),
                if (chat.isMuted)
                  Padding(padding: const EdgeInsets.only(right: 3),
                      child: Icon(Icons.notifications_off_rounded, size: 13, color: Colors.white.withValues(alpha: 0.4))),
                if (chat.isPinned)
                  const Padding(padding: EdgeInsets.only(right: 3),
                      child: Icon(Icons.push_pin, size: 13, color: Colors.white)),
                Expanded(child: Text(chat.title,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.white),
                    overflow: TextOverflow.ellipsis)),
              ]),
              if (chat.lastMessage != null)
                Text(chat.lastMessage!, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.muted)),
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
    );
  }

  void _showChatContextMenu(Chat chat) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          // Заголовок
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              ColoredAvatar(
                imageUrl: chat.imageUrl,
                title: chat.title,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(chat.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
          const Divider(color: AppColors.border, height: 1),
          // Закрепить / Открепить
          if (chat.isPinned)
            ListTile(
              leading: const Icon(Icons.push_pin, color: Colors.white, size: 20),
              title: const Text('Открепить', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _api.updateChatPreferences(chat.id, isPinned: false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Чат откреплён'), duration: Duration(seconds: 1)),
                );
                _load();
              },
            )
          else
            ListTile(
              leading: const Icon(Icons.push_pin_outlined, color: Colors.white, size: 20),
              title: const Text('Закрепить', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _api.updateChatPreferences(chat.id, isPinned: true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Чат закреплён'), duration: Duration(seconds: 1)),
                );
                _load();
              },
            ),
          // В архив / Вернуть из архива
          if (chat.isArchived)
            ListTile(
              leading: const Icon(Icons.unarchive_outlined, color: Colors.white, size: 20),
              title: const Text('Вернуть из архива', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _api.updateChatPreferences(chat.id, isArchived: false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Чат возвращён из архива'), duration: Duration(seconds: 1)),
                );
                _load();
              },
            )
          else
            ListTile(
              leading: const Icon(Icons.archive_outlined, color: Colors.white, size: 20),
              title: const Text('В архив', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _api.updateChatPreferences(chat.id, isArchived: true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Чат в архиве'), duration: Duration(seconds: 1)),
                );
                _load();
              },
            ),
          // Заглушить / Включить уведомления
          if (chat.isMuted)
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined, color: Colors.white, size: 20),
              title: const Text('Включить уведомления', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _api.updateChatPreferences(chat.id, isMuted: false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Уведомления включены'), duration: Duration(seconds: 1)),
                );
                _load();
              },
            )
          else
            ListTile(
              leading: const Icon(Icons.notifications_off_outlined, color: Colors.white, size: 20),
              title: const Text('Заглушить', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _api.updateChatPreferences(chat.id, isMuted: true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Уведомления заглушены'), duration: Duration(seconds: 1)),
                );
              },
            ),
          const Divider(color: AppColors.border, height: 1),
          // Удалить у меня
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20),
            title: const Text('Удалить у меня', style: TextStyle(color: Color(0xFFEF4444))),
            onTap: () async {
              Navigator.pop(ctx);
              final ok = await _api.leaveChat(chat.id);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok ? 'Чат удалён' : 'Не удалось удалить чат'),
                  duration: const Duration(seconds: 1),
                ),
              );
              if (ok) _load();
            },
          ),
          // Удалить у всех
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Color(0xFFEF4444), size: 20),
            title: const Text('Удалить у всех', style: TextStyle(color: Color(0xFFEF4444))),
            onTap: () async {
              Navigator.pop(ctx);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  backgroundColor: AppColors.surfaceAlt,
                  title: const Text('Удалить чат у всех?', style: TextStyle(color: Colors.white)),
                  content: const Text('Это действие нельзя отменить.',
                      style: TextStyle(color: Colors.white70)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Отмена'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Удалить', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
              if (confirm != true || !mounted) return;
              final ok = await _api.deleteChat(chat.id);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok ? 'Чат удалён' : 'Не удалось удалить чат'),
                  duration: const Duration(seconds: 1),
                ),
              );
              if (ok) _load();
            },
          ),
          // Заблокировать (только для приватных)
          if (chat.type == 'PRIVATE' && chat.partnerId != null)
            ListTile(
              leading: const Icon(Icons.block, color: Color(0xFFEF4444), size: 20),
              title: const Text('Заблокировать', style: TextStyle(color: Color(0xFFEF4444))),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await _api.blockUser(chat.partnerId!);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Пользователь заблокирован' : 'Не удалось заблокировать'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
  Widget _buildServerTile(Map<String, dynamic> server) {
    final name = server['name'] as String? ?? 'Сервер';
    final image = server['imageUrl'] as String?;
    final chats = (server['chats'] as List?) ?? [];

    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => ServerChannelsScreen(server: server),
      )).then((_) => _load()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          ColoredAvatar(
            imageUrl: image,
            title: name,
            size: 52,
            borderRadius: BorderRadius.circular(14),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.dns_rounded, size: 14, color: AppColors.primary),
              const SizedBox(width: 4),
              Expanded(child: Text(name,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.white),
                  overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 2),
            Text('${chats.length} каналов',
                style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          ])),
          const Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
        ]),
      ),
    );
  }

  void _showMainMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF16161B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _MenuTile(
                icon: Icons.add_circle_outline_rounded,
                label: 'Новый чат',
                subtitle: 'Группа, канал или сервер',
                onTap: () { Navigator.pop(context); _showCreateMenu(); },
              ),
              _MenuTile(
                icon: Icons.person_outline_rounded,
                label: 'Профиль',
                subtitle: 'Имя, статус, соц. сети',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen()));
                },
              ),
              _MenuTile(
                icon: Icons.settings_outlined,
                label: 'Настройки',
                subtitle: 'Приватность, уведомления, тема',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()));
                },
              ),
              const SizedBox(height: 12),
            ],
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
  final String? id;
  const _Avatar({required this.imageUrl, required this.name,
      this.isChannel = false, this.isGroup = false, this.id});

  /// Проверка: это hex-цвет, сохранённый в БД через `generateAvatarColor()`
  /// (см. `lib/avatar.ts` в Next.js проекте)?
  static bool _isHex(String? s) =>
      s != null && s.startsWith('#') && (s.length == 7 || s.length == 9 || s.length == 4);

  /// Генерирует яркий цвет из строки — используется ТОЛЬКО как идентификатор
  /// собеседника для приватных чатов без аватара (имитация Telegram).
  static Color _colorFromString(String s) {
    const colors = [
      Color(0xFFE17076), // красный
      Color(0xFFEDA86C), // оранжевый
      Color(0xFFA695E7), // фиолетовый
      Color(0xFF7BC862), // зелёный
      Color(0xFF6EC9CB), // бирюзовый
      Color(0xFF65AADD), // синий
      Color(0xFFEE7AAE), // розовый
      Color(0xFFE5C65B), // жёлтый
    ];
    int hash = 0;
    for (int i = 0; i < s.length; i++) {
      hash = s.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return colors[hash.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    // 1) hex-цвет из БД или http(s)-картинка → отдаём универсальному виджету
    if (_isHex(imageUrl) || (imageUrl != null && imageUrl!.isNotEmpty)) {
      return ColoredAvatar(
        imageUrl: imageUrl,
        title: name,
        size: 52,
      );
    }
    // 2) Нет аватара вовсе → стабильный цвет по id (приятнее, чем серый кружок)
    final color = _colorFromString(id ?? name);
    return Container(
      width: 52, height: 52,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: Center(child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white),
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


class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(children: [
        Icon(icon, size: 22, color: Colors.white.withValues(alpha: 0.7)),
        const SizedBox(width: 16),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(
                fontSize: 12, color: Colors.white.withValues(alpha: 0.4))),
          ],
        )),
        Icon(Icons.chevron_right_rounded,
            size: 20, color: Colors.white.withValues(alpha: 0.2)),
      ]),
    ),
  );
}
