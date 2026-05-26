import 'package:flutter/material.dart';
import '../main.dart';
import '../models/chat.dart';
import '../services/api_service.dart';
import '../widgets/colored_avatar.dart';
import 'chat_screen.dart';
import 'chat_info_screen.dart';

/// Экран подканалов сервера — как в Telegram при тапе на сервер.
/// Шапка: аватар + название + участники.
/// Тело: список каналов с последним сообщением, временем, непрочитанными.
class ServerChannelsScreen extends StatefulWidget {
  final Map<String, dynamic> server;
  const ServerChannelsScreen({super.key, required this.server});

  @override
  State<ServerChannelsScreen> createState() => _ServerChannelsScreenState();
}

class _ServerChannelsScreenState extends State<ServerChannelsScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _channels = [];
  bool _loading = true;

  String get _name => widget.server['name'] ?? 'Сервер';
  String? get _image => widget.server['imageUrl'] as String?;
  int get _membersCount => (widget.server['_count']?['members'] as int?) ?? (widget.server['members'] as List?)?.length ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Загружаем полные данные сервера с подканалами
    final res = await _api.getChatDetails(widget.server['id'] ?? '');
    if (res != null && mounted) {
      final chats = (res['chats'] as List?) ?? [];
      setState(() {
        _channels = chats.map((c) => Map<String, dynamic>.from(c as Map)).toList();
        _loading = false;
      });
    } else {
      // Fallback: используем данные из sidebar
      setState(() {
        _channels = ((widget.server['chats'] as List?) ?? [])
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChatInfoScreen(chat: Chat(
              id: widget.server['id'] ?? '', title: _name, type: 'SERVER', imageUrl: _image,
            )),
          )),
          child: Row(children: [
            // Server avatar
            ColoredAvatar(
              imageUrl: _image,
              title: _name,
              size: 40,
              borderRadius: BorderRadius.circular(12),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
                  overflow: TextOverflow.ellipsis),
              Text('$_membersCount участников',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
            ])),
          ]),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search, color: Colors.white), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert, color: Colors.white), onPressed: () {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => ChatInfoScreen(chat: Chat(
                id: widget.server['id'] ?? '', title: _name, type: 'SERVER', imageUrl: _image,
              )),
            ));
          }),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _channels.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.tag, size: 48, color: Colors.white.withValues(alpha: 0.2)),
                  const SizedBox(height: 12),
                  Text('Нет каналов', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
                ]))
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _channels.length,
                    itemBuilder: (_, i) => _buildChannelTile(_channels[i]),
                  ),
                ),
    );
  }

  Widget _buildChannelTile(Map<String, dynamic> channel) {
    final name = channel['name'] ?? 'Канал';
    final type = channel['type'] as String? ?? 'GROUP';
    final isChannel = type == 'CHANNEL';
    final lastMsg = channel['lastMessage'] as Map<String, dynamic>?;
    final unread = channel['unreadCount'] as int? ?? 0;
    final image = channel['imageUrl'] as String?;

    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(chat: Chat(
          id: channel['id'] ?? '', title: name, type: type, imageUrl: image,
        )),
      )).then((_) => _load()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04))),
        ),
        child: Row(children: [
          // Channel icon/avatar (цвет из БД, как в веб-версии)
          ColoredAvatar(
            imageUrl: image,
            title: name,
            size: 48,
            borderRadius: BorderRadius.circular(14),
          ),
          const SizedBox(width: 12),
          // Name + last message
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (isChannel)
                Padding(padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.tag, size: 14, color: AppColors.primary)),
              Expanded(child: Text(name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                  overflow: TextOverflow.ellipsis)),
              if (lastMsg != null) ...[
                const SizedBox(width: 8),
                Text(_formatTime(lastMsg['createdAt']),
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4))),
              ],
            ]),
            const SizedBox(height: 3),
            if (lastMsg != null)
              Text(
                '${lastMsg['senderName'] ?? ''}: ${lastMsg['content'] ?? ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5)),
              )
            else
              Text(isChannel ? 'Канал' : 'Группа',
                  style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.3))),
          ])),
          // Unread badge
          if (unread > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$unread',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      ),
    );
  }

  String _formatTime(dynamic createdAt) {
    if (createdAt == null) return '';
    try {
      final dt = DateTime.parse(createdAt.toString());
      final now = DateTime.now();
      if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      return '${dt.day}.${dt.month.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }
}
