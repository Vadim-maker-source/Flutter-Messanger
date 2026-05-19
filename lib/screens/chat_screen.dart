import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../services/pusher_service.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../main.dart' show navigatorKey;
import 'call_screen.dart';
import 'media_recorder.dart';
import 'media_widgets.dart';

// Цвета точно из RealTimeChat.tsx
class _C {
  static const bg         = Color(0xFF1B1929);
  static const myBubble   = Color(0xFF7166D8);
  static const theirBubble= Color(0xFF18181B); // zinc-900
  static const inputBg    = Color(0x0DFFFFFF); // white/5
  static const timeFg     = Color(0x66FFFFFF); // white/40
  static const nameFg     = Color(0xFF7166D8);
  static const headerBg   = Color(0x701B1929); // #1b192970
  static const divider    = Color(0x1AFFFFFF); // white/10
  static const dateBg     = Color(0x14FFFFFF); // white/8
  static const sendBtn    = Color(0xFF7166D8);
  static const avatarBg   = Color(0x337166D8); // violet-500/20
  static const readColor  = Colors.white;
  static const unreadColor= Color(0x66FFFFFF); // white/40
}

class ChatScreen extends StatefulWidget {
  final Chat chat;
  const ChatScreen({super.key, required this.chat});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _api = ApiService();
  final _pusher = PusherService();
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  List<Message> _messages = [];
  bool _isLoading = true;
  bool _uploading = false;
  String? _myId;
  final Set<String> _sentIds = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final profile = await _api.getProfile();
    _myId = profile?.id;
    await _loadMessages();
    _pusher.subscribeToChat(widget.chat.id,
      onNewMessage: (data) {
        if (!mounted) return;
        final msg = Message.fromJson(data);
        if (_sentIds.contains(msg.id)) { _sentIds.remove(msg.id); return; }
        if (_messages.any((m) => m.id == msg.id)) return;
        setState(() => _messages.add(msg));
        _scrollToBottom(animate: true);
        _api.markAsRead(widget.chat.id);
      },
      onMessageUpdated: (data) {
        if (!mounted) return;
        final u = Message.fromJson(data);
        setState(() {
          final i = _messages.indexWhere((m) => m.id == u.id);
          if (i != -1) _messages[i] = u;
        });
      },
      onMessageDeleted: (id) {
        if (!mounted) return;
        setState(() => _messages.removeWhere((m) => m.id == id));
      },
    );
    // Pusher: messages-read
    _pusher.subscribeToChat(widget.chat.id,
      onNewMessage: (_) {},
    );
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    final msgs = await _api.getMessages(widget.chat.id);
    setState(() { _messages = msgs; _isLoading = false; });
    await _api.markAsRead(widget.chat.id);
    _scrollToBottom();
  }

  void _scrollToBottom({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      if (animate) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    final msg = await _api.sendMessage(widget.chat.id, text);
    if (msg != null && mounted) {
      _sentIds.add(msg.id);
      setState(() => _messages.add(msg));
      _scrollToBottom(animate: true);
    }
  }

  Future<void> _sendFile(File file, String mimeType, String fileType) async {
    setState(() => _uploading = true);
    final result = await _api.uploadFile(file, mimeType);
    if (result == null) { setState(() => _uploading = false); return; }
    final msg = await _api.sendMessage(widget.chat.id, '',
        fileUrl: result['url'], fileType: fileType);
    setState(() => _uploading = false);
    if (msg != null && mounted) {
      _sentIds.add(msg.id);
      setState(() => _messages.add(msg));
      _scrollToBottom(animate: true);
    }
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E22),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: _C.divider, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: GridView.count(crossAxisCount: 4, shrinkWrap: true,
            mainAxisSpacing: 8, crossAxisSpacing: 12,
            children: [
              _AttachBtn(icon: Icons.photo_library_rounded, label: 'Фото',
                  color: const Color(0xFF0EA5E9),
                  onTap: () async { Navigator.pop(context); final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85); if (x != null) _sendFile(File(x.path), 'image/jpeg', 'IMAGE'); }),
              _AttachBtn(icon: Icons.videocam_rounded, label: 'Видео',
                  color: const Color(0xFF8B5CF6),
                  onTap: () async { Navigator.pop(context); final x = await ImagePicker().pickVideo(source: ImageSource.gallery); if (x != null) _sendFile(File(x.path), 'video/mp4', 'VIDEO'); }),
              _AttachBtn(icon: Icons.insert_drive_file_rounded, label: 'Файл',
                  color: const Color(0xFF059669),
                  onTap: () async { Navigator.pop(context); final r = await FilePicker.platform.pickFiles(); if (r?.files.single.path != null) _sendFile(File(r!.files.single.path!), 'application/octet-stream', 'FILE'); }),
              _AttachBtn(icon: Icons.camera_alt_rounded, label: 'Камера',
                  color: _C.myBubble,
                  onTap: () async { Navigator.pop(context); final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85); if (x != null) _sendFile(File(x.path), 'image/jpeg', 'IMAGE'); }),
              _AttachBtn(icon: Icons.mic_rounded, label: 'Голос',
                  color: Colors.red,
                  onTap: () { Navigator.pop(context); showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, builder: (_) => VoiceRecorderSheet(onDone: (f) => _sendFile(f, 'audio/m4a', 'AUDIO'))); }),
              _AttachBtn(icon: Icons.radio_button_checked_rounded, label: 'Кружок',
                  color: const Color(0xFFF59E0B),
                  onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => VideoNoteRecorder(onDone: (f) => _sendFile(f, 'video/mp4', 'ROUND')))); }),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ])),
    );
  }

  void _showMenu(Message msg) {
    if (msg.userId != _myId) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E22),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: _C.divider, borderRadius: BorderRadius.circular(2))),
        if (msg.fileUrl == null)
          ListTile(
            leading: const Icon(Icons.edit_rounded, color: _C.myBubble, size: 20),
            title: const Text('Редактировать', style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); _editMessage(msg); },
          ),
        ListTile(
          leading: const Icon(Icons.delete_rounded, color: Colors.red, size: 20),
          title: const Text('Удалить', style: TextStyle(color: Colors.red)),
          onTap: () async {
            Navigator.pop(context);
            await _api.deleteMessage(msg.id);
            if (mounted) setState(() => _messages.removeWhere((m) => m.id == msg.id));
          },
        ),
        const SizedBox(height: 8),
      ])),
    );
  }

  void _editMessage(Message msg) {
    final ctrl = TextEditingController(text: msg.content);
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E22),
      title: const Text('Редактировать', style: TextStyle(color: Colors.white)),
      content: TextField(controller: ctrl, autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Текст сообщения')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.4)))),
        TextButton(
          onPressed: () async {
            final t = ctrl.text.trim();
            Navigator.pop(context);
            if (t.isEmpty) return;
            await _api.editMessage(msg.id, t);
            if (mounted) setState(() {
              final i = _messages.indexWhere((m) => m.id == msg.id);
              if (i != -1) _messages[i] = Message(
                id: msg.id, chatId: msg.chatId, userId: msg.userId,
                content: t, createdAt: msg.createdAt, updatedAt: DateTime.now(),
                user: msg.user, fileUrl: msg.fileUrl, fileType: msg.fileType,
                readReceipts: msg.readReceipts,
              );
            });
          },
          child: const Text('Сохранить', style: TextStyle(color: _C.myBubble)),
        ),
      ],
    ));
  }

  @override
  void dispose() {
    _pusher.unsubscribe(widget.chat.id);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isChannel = widget.chat.type == 'CHANNEL';
    final canWrite = !isChannel || widget.chat.role == 'CREATOR' || widget.chat.role == 'ADMIN';

    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _buildAppBar(),
      body: Column(children: [
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: _C.myBubble))
              : _messages.isEmpty
                  ? _buildEmpty()
                  : ListView.builder(
                      controller: _scroll,
                      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) {
                        final msg = _messages[i];
                        final isMe = msg.userId == _myId;
                        final prev = i > 0 ? _messages[i - 1] : null;
                        final showDate = prev == null ||
                            !_sameDay(prev.createdAt, msg.createdAt);
                        final showAvatar = !isMe &&
                            (prev == null || prev.userId != msg.userId ||
                             showDate);
                        final isGroup = widget.chat.type == 'GROUP' ||
                            widget.chat.type == 'CHANNEL';
                        return Column(children: [
                          if (showDate) _DateDivider(msg.createdAt),
                          _MessageBubble(
                            msg: msg,
                            isMe: isMe,
                            showAvatar: showAvatar,
                            showName: showAvatar && isGroup,
                            myId: _myId ?? '',
                            isPrivate: widget.chat.type == 'PRIVATE',
                            onLongPress: () => _showMenu(msg),
                          ),
                        ]);
                      },
                    ),
        ),
        if (_uploading)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF1E1E22),
            child: Row(children: [
              const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _C.myBubble)),
              const SizedBox(width: 10),
              Text('Загрузка...', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.4))),
            ]),
          ),
        if (canWrite) _buildInput() else _buildReadOnly(),
      ]),
    );
  }

  Future<void> _startCall(String type) async {
    final data = await _api.startCall(widget.chat.id, type);
    if (data == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось начать звонок')),
      );
    }
    // CallScreen откроется через Pusher outgoing-call событие в main.dart
  }

  PreferredSizeWidget _buildAppBar() {
    final isPrivate = widget.chat.type == 'PRIVATE';
    final isChannel = widget.chat.type == 'CHANNEL';
    return AppBar(
      backgroundColor: _C.headerBg,
      elevation: 0,
      titleSpacing: 0,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          color: _C.headerBg,
          border: Border(bottom: BorderSide(color: _C.divider)),
        ),
      ),
      title: Row(children: [
        // Аватар
        Stack(children: [
          widget.chat.imageUrl != null
              ? CircleAvatar(backgroundImage: NetworkImage(widget.chat.imageUrl!), radius: 22)
              : CircleAvatar(radius: 22, backgroundColor: _C.avatarBg,
                  child: Text(
                    widget.chat.title.isNotEmpty ? widget.chat.title[0].toUpperCase() : '?',
                    style: const TextStyle(color: _C.myBubble, fontWeight: FontWeight.w700, fontSize: 16),
                  )),
        ]),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.chat.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
              overflow: TextOverflow.ellipsis),
          Text(
            isPrivate ? 'в сети' : isChannel ? 'Канал' : 'Группа',
            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
          ),
        ])),
      ]),
      actions: [
        IconButton(
          icon: const Icon(Icons.phone, color: Colors.white),
          onPressed: () => _startCall('audio'),
          tooltip: 'Аудиозвонок',
        ),
        IconButton(
          icon: const Icon(Icons.videocam, color: Colors.white),
          onPressed: () => _startCall('video'),
          tooltip: 'Видеозвонок',
        ),
      ],
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 56, height: 56,
          decoration: BoxDecoration(color: _C.myBubble.withOpacity(0.1),
              borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.chat_bubble_outline_rounded, size: 28, color: _C.myBubble)),
      const SizedBox(height: 12),
      const Text('Нет сообщений', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
      const SizedBox(height: 4),
      Text('Напишите первым!', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.4))),
    ]),
  );

  // Инпут точно как в RealTimeChat: bg-white/5 rounded-full
  Widget _buildInput() => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    color: _C.bg,
    child: Row(children: [
      // Скрепка: p-3 bg-white/5 rounded-full
      GestureDetector(
        onTap: _showAttachMenu,
        child: Container(
          width: 46, height: 46,
          decoration: BoxDecoration(color: _C.inputBg, shape: BoxShape.circle),
          child: const Icon(Icons.attach_file_rounded, color: Colors.white, size: 22),
        ),
      ),
      const SizedBox(width: 8),
      // Поле: bg-white/5 rounded-full px-6 py-4
      Expanded(child: Container(
        decoration: BoxDecoration(color: _C.inputBg, borderRadius: BorderRadius.circular(30)),
        child: Row(children: [
          const SizedBox(width: 20),
          Expanded(child: TextField(
            controller: _ctrl,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Сообщение...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onSubmitted: (_) => _send(),
          )),
          const SizedBox(width: 8),
        ]),
      )),
      const SizedBox(width: 8),
      // Кнопка отправки: bg-[#7166D8] p-3.5 rounded-full
      GestureDetector(
        onTap: _send,
        child: Container(
          width: 46, height: 46,
          decoration: const BoxDecoration(color: _C.sendBtn, shape: BoxShape.circle),
          child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
        ),
      ),
    ]),
  );

  Widget _buildReadOnly() => Container(
    padding: const EdgeInsets.all(16),
    color: _C.bg,
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.lock_outline_rounded, size: 14, color: _C.timeFg),
      const SizedBox(width: 6),
      Text('Только администраторы могут писать',
          style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.4))),
    ]),
  );

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ─── Разделитель дат ─────────────────────────────────────────────────────────

class _DateDivider extends StatelessWidget {
  final DateTime date;
  const _DateDivider(this.date);

  String get _label {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Сегодня';
    if (d == today.subtract(const Duration(days: 1))) return 'Вчера';
    return DateFormat('d MMMM yyyy', 'ru').format(date);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Center(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF), // white/8
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(_label,
          style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5))),
    )),
  );
}

// ─── Пузырь сообщения ────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final Message msg;
  final bool isMe;
  final bool showAvatar;
  final bool showName;
  final String myId;
  final bool isPrivate;
  final VoidCallback onLongPress;

  const _MessageBubble({
    required this.msg, required this.isMe, required this.showAvatar,
    required this.showName, required this.myId, required this.isPrivate,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: showAvatar ? 8 : 2, bottom: 2),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Аватар чужого
          if (!isMe) ...[
            showAvatar
                ? _buildAvatar()
                : const SizedBox(width: 40),
            const SizedBox(width: 8),
          ],

          Flexible(child: GestureDetector(
            onLongPress: onLongPress,
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.70),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF7166D8) : const Color(0xFF18181B),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                border: isMe ? null : Border.all(color: const Color(0x1AFFFFFF)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2),
                    blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Имя (только в группах для чужих)
                if (showName && msg.user != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 14, right: 14, top: 10, bottom: 2),
                    child: Text(
                      (msg.user!.displayName.isNotEmpty
                          ? msg.user!.displayName
                          : msg.user!.username).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: Color(0xFF7166D8), letterSpacing: 0.8,
                      ),
                    ),
                  ),

                // Контент
                Padding(
                  padding: _contentPadding,
                  child: _buildContent(),
                ),

                // Время + статус прочтения
                Padding(
                  padding: const EdgeInsets.only(right: 12, bottom: 8, left: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Иконка редактирования
                      if (msg.updatedAt != null &&
                          msg.updatedAt!.difference(msg.createdAt).inMilliseconds > 2000)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.edit, size: 12,
                              color: Colors.white.withOpacity(0.3)),
                        ),
                      Text(
                        DateFormat('HH:mm').format(msg.createdAt),
                        style: TextStyle(fontSize: 12,
                            color: Colors.white.withOpacity(0.4)),
                      ),
                      // Read receipts — только для своих
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        _buildReadStatus(),
                      ],
                    ],
                  ),
                ),
              ]),
            ),
          )),

          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }

  EdgeInsets get _contentPadding {
    if (msg.fileType == 'IMAGE' || msg.fileType == 'VIDEO' || msg.fileType == 'ROUND') {
      return const EdgeInsets.only(top: 4, left: 4, right: 4);
    }
    return const EdgeInsets.only(left: 14, right: 14, top: 8, bottom: 2);
  }

  Widget _buildContent() {
    if (msg.fileUrl != null) {
      switch (msg.fileType) {
        case 'IMAGE': return ImageMessage(url: msg.fileUrl!);
        case 'VIDEO': return VideoMessage(url: msg.fileUrl!);
        case 'ROUND': return RoundVideoMessage(url: msg.fileUrl!);
        case 'AUDIO': return AudioMessage(url: msg.fileUrl!, isMe: isMe);
        default: return FileMessage(url: msg.fileUrl!, fileName: msg.fileName ?? msg.content, isMe: isMe);
      }
    }
    return Text(msg.content,
        style: const TextStyle(fontSize: 15, color: Colors.white, height: 1.4));
  }

  // Галочки прочтения как в RealTimeChat
  Widget _buildReadStatus() {
    final isRead = msg.readReceipts.any((r) => r.userId != myId);
    if (isPrivate) {
      // Приватный: одна галочка / двойная
      return Icon(
        isRead ? Icons.done_all_rounded : Icons.done_rounded,
        size: 16,
        color: isRead ? Colors.white : Colors.white.withOpacity(0.4),
      );
    } else {
      // Группа: галочка + число прочитавших
      final count = msg.readReceipts.where((r) => r.userId != myId).length;
      if (count == 0) {
        return Icon(Icons.done_rounded, size: 10,
            color: Colors.white.withOpacity(0.4));
      }
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.done_all_rounded, size: 10, color: Color(0xFF60A5FA)),
        const SizedBox(width: 2),
        Text('$count', style: const TextStyle(fontSize: 10, color: Color(0xFF60A5FA))),
      ]);
    }
  }

  Widget _buildAvatar() {
    final name = msg.user?.displayName.isNotEmpty == true
        ? msg.user!.displayName
        : msg.user?.username ?? '?';
    return msg.user?.avatarUrl != null
        ? CircleAvatar(backgroundImage: NetworkImage(msg.user!.avatarUrl!), radius: 20)
        : CircleAvatar(radius: 20, backgroundColor: const Color(0x337166D8),
            child: Text(name[0].toUpperCase(),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: Color(0xFF7166D8))));
  }
}

// ─── Кнопка прикрепления ─────────────────────────────────────────────────────

class _AttachBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _AttachBtn({required this.icon, required this.label,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 56, height: 56,
          decoration: BoxDecoration(color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16)),
          child: Icon(icon, color: color, size: 26)),
      const SizedBox(height: 4),
      Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.5))),
    ]),
  );
}
