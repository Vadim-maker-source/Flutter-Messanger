import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../services/pusher_service_ws.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../main.dart' show AppColors;

import 'media_recorder.dart';
import 'media_widgets.dart';


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
  final _focusNode = FocusNode();

  List<Message> _messages = [];
  bool _isLoading = true;
  bool _uploading = false;
  String? _myId;
  final Set<String> _sentIds = {};

  // Typing indicator
  final Map<String, String> _typingUsers = {}; // userId -> displayName
  bool _isTyping = false;
  DateTime? _lastTypingSent;

  // Online status
  bool _partnerOnline = false;

  // Pagination
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;
  static const _pageSize = 30;

  // Edit mode
  Message? _editingMsg;
  Message? _replyingTo;

  // Reactions map: emoji -> key
  static const _reactions = {
    '❤️': 'heart', '👍': 'like', '😂': 'laugh',
    '😮': 'wow',   '😢': 'sad',  '😡': 'angry',
  };

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _init();
  }

  void _onScroll() {
    if (_scroll.position.pixels <= 80 && _hasMore && !_loadingMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final older = await _api.getMessagesPaginated(
        widget.chat.id, page: _page + 1, limit: _pageSize);
    if (!mounted) return;
    if (older.isEmpty) {
      setState(() { _hasMore = false; _loadingMore = false; });
      return;
    }
    final prevOffset = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    setState(() {
      _messages = [...older, ..._messages];
      _page++;
      _loadingMore = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent - prevOffset);
      }
    });
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
      onMessagesRead: (readIds) {
        if (!mounted) return;
        setState(() {
          for (int i = 0; i < _messages.length; i++) {
            if (readIds.contains(_messages[i].id)) {
              final msg = _messages[i];
              final alreadyRead = msg.readReceipts.any((r) => r.userId != _myId);
              if (!alreadyRead) {
                _messages[i] = Message(
                  id: msg.id, chatId: msg.chatId, userId: msg.userId,
                  content: msg.content, createdAt: msg.createdAt,
                  updatedAt: msg.updatedAt, user: msg.user,
                  fileUrl: msg.fileUrl, fileType: msg.fileType,
                  readReceipts: [...msg.readReceipts, ReadReceipt(userId: _myId ?? '', readAt: DateTime.now())],
                );
              }
            }
          }
        });
      },
      onTypingStart: (userId, displayName) {
        if (!mounted || userId == _myId) return;
        setState(() => _typingUsers[userId] = displayName);
      },
      onTypingStop: (userId) {
        if (!mounted) return;
        setState(() => _typingUsers.remove(userId));
      },
      onReactionUpdated: (messageId, reactions) {
        if (!mounted) return;
        setState(() {
          final i = _messages.indexWhere((m) => m.id == messageId);
          if (i != -1) {
            final m = _messages[i];
            _messages[i] = Message(
              id: m.id, chatId: m.chatId, userId: m.userId,
              content: m.content, createdAt: m.createdAt, updatedAt: m.updatedAt,
              user: m.user, fileUrl: m.fileUrl, fileType: m.fileType,
              readReceipts: m.readReceipts, reactions: reactions,
            );
          }
        });
      },
    );
    _pusher.subscribeToPresence((userId, isOnline, _) {
      if (!mounted) return;
      // Для приватного чата — показываем статус собеседника
      if (widget.chat.type == 'PRIVATE') {
        setState(() => _partnerOnline = isOnline);
      }
    });
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    final msgs = await _api.getMessagesPaginated(
        widget.chat.id, page: 1, limit: _pageSize);
    setState(() {
      _messages = msgs;
      _isLoading = false;
      _page = 1;
      _hasMore = msgs.length >= _pageSize;
    });
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
    if (_editingMsg != null) {
      await _editMessage(_editingMsg!);
      return;
    }
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    _stopTyping();
    final replyId = _replyingTo?.id;
    setState(() => _replyingTo = null);
    final msg = await _api.sendMessage(widget.chat.id, text, replyToId: replyId);
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

  void _onTextChanged(String value) {
    final now = DateTime.now();
    if (value.isNotEmpty && (_lastTypingSent == null ||
        now.difference(_lastTypingSent!).inSeconds >= 3)) {
      _lastTypingSent = now;
      _isTyping = true;
      _api.sendTyping(widget.chat.id, true);
    } else if (value.isEmpty && _isTyping) {
      _stopTyping();
    }
  }

  void _stopTyping() {
    if (_isTyping) {
      _isTyping = false;
      _lastTypingSent = null;
      _api.sendTyping(widget.chat.id, false);
    }
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
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
                  color: AppColors.primary,
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

  void _showMessageMenu(Message msg) {
    final isMe = msg.userId == _myId;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
        // Быстрые реакции
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _reactions.entries.map((e) {
              final userReacted = (msg.reactions?[e.value] as List?)
                  ?.contains(_myId) ?? false;
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  _toggleReaction(msg, e.value);
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: userReacted
                        ? AppColors.primary.withValues(alpha: 0.3)
                        : AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(e.key, style: const TextStyle(fontSize: 26)),
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(color: AppColors.border, height: 1),
        // Ответить
        ListTile(
          leading: const Icon(Icons.reply_rounded, color: Color(0xFFFB923C), size: 20),
          title: const Text('Ответить', style: TextStyle(color: Colors.white)),
          onTap: () {
            Navigator.pop(context);
            setState(() {
              _replyingTo = msg;
              _editingMsg = null;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
          },
        ),
        // Переслать
        ListTile(
          leading: const Icon(Icons.forward_rounded, color: Color(0xFF60A5FA), size: 20),
          title: const Text('Переслать', style: TextStyle(color: Colors.white)),
          onTap: () { Navigator.pop(context); _showForwardDialog(msg); },
        ),
        // Копировать текст (только если есть текст)
        if (msg.content.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.copy_rounded, color: Color(0xFF4ADE80), size: 20),
            title: const Text('Копировать текст', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              Clipboard.setData(ClipboardData(text: msg.content));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Текст скопирован'), duration: Duration(seconds: 1)),
              );
            },
          ),
        if (isMe && msg.fileUrl == null)
          ListTile(
            leading: const Icon(Icons.edit_rounded, color: AppColors.primary, size: 20),
            title: const Text('Редактировать', style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); _startEdit(msg); },
          ),
        if (isMe)
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

  void _showForwardDialog(Message msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Переслать в...', style: TextStyle(color: Colors.white)),
        content: const Text('Функция пересылки: выберите чат в списке',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть', style: TextStyle(color: AppColors.primary))),
        ],
      ),
    );
  }

  void _toggleReaction(Message msg, String reactionKey) {
    final users = (msg.reactions?[reactionKey] as List?)
        ?.map((e) => e.toString()).toList() ?? [];
    final alreadyReacted = users.contains(_myId);
    if (alreadyReacted) {
      _api.removeReaction(msg.id, reactionKey);
    } else {
      _api.addReaction(msg.id, reactionKey);
    }
  }

  void _startEdit(Message msg) {
    setState(() {
      _editingMsg = msg;
      _ctrl.text = msg.content;
    });
    // Фокус на поле ввода
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  void _cancelEdit() {
    setState(() { _editingMsg = null; _ctrl.clear(); });
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  Future<void> _editMessage(Message msg) async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() { _editingMsg = null; _ctrl.clear(); });
    await _api.editMessage(msg.id, text);
    if (mounted) setState(() {
      final i = _messages.indexWhere((m) => m.id == msg.id);
      if (i != -1) _messages[i] = Message(
        id: msg.id, chatId: msg.chatId, userId: msg.userId,
        content: text, createdAt: msg.createdAt, updatedAt: DateTime.now(),
        user: msg.user, fileUrl: msg.fileUrl, fileType: msg.fileType,
        readReceipts: msg.readReceipts, reactions: msg.reactions,
      );
    });
  }

  @override
  void dispose() {
    _stopTyping();
    _pusher.unsubscribe(widget.chat.id);
    _pusher.unsubscribeFromPresence();
    _ctrl.dispose();
    _scroll.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isChannel = widget.chat.type == 'CHANNEL';
    final canWrite = !isChannel || widget.chat.role == 'CREATOR' || widget.chat.role == 'ADMIN';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: Column(children: [
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _messages.isEmpty
                  ? _buildEmpty()
                  : ListView.builder(
                      controller: _scroll,
                      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: _messages.length + (_loadingMore ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i == 0 && _loadingMore) {
                          return const Padding(
                            padding: EdgeInsets.all(8),
                            child: Center(child: SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))),
                          );
                        }
                        final idx = _loadingMore ? i - 1 : i;
                        final msg = _messages[idx];
                        final isMe = msg.userId == _myId;
                        final prev = idx > 0 ? _messages[idx - 1] : null;
                        final showDate = prev == null ||
                            !_sameDay(prev.createdAt, msg.createdAt);
                        final showAvatar = !isMe &&
                            (prev == null || prev.userId != msg.userId || showDate);
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
                            onLongPress: () => _showMessageMenu(msg),
                            onReactionTap: (key) => _toggleReaction(msg, key),
                          ),
                        ]);
                      },
                    ),
        ),
        // Typing indicator
        if (_typingUsers.isNotEmpty)
          _TypingIndicator(names: _typingUsers.values.toList()),
        if (_uploading)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.surfaceAlt,
            child: Row(children: [
              const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
              const SizedBox(width: 10),
              Text('Загрузка...', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6))),
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
      backgroundColor: AppColors.surface,
      elevation: 0,
      titleSpacing: 0,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
      ),
      title: Row(children: [
        // Аватар
        Stack(children: [
          widget.chat.imageUrl != null
              ? CircleAvatar(backgroundImage: NetworkImage(widget.chat.imageUrl!), radius: 22)
              : CircleAvatar(radius: 22, backgroundColor: const Color(0x206C3EF4),
                  child: Text(
                    widget.chat.title.isNotEmpty ? widget.chat.title[0].toUpperCase() : '?',
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16),
                  )),
        ]),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.chat.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
              overflow: TextOverflow.ellipsis),
          Text(
            isPrivate
                ? (_partnerOnline ? 'в сети' : 'не в сети')
                : isChannel ? 'Канал' : 'Группа',
            style: TextStyle(
              fontSize: 12,
              color: isPrivate && _partnerOnline
                  ? const Color(0xFF4ADE80)
                  : Colors.white.withValues(alpha: 0.5),
            ),
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
      Image.asset('assets/mascotNoMessages.png', width: 120, height: 120),
      const SizedBox(height: 12),
      const Text('Нет сообщений', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
      const SizedBox(height: 4),
      Text('Напишите первым!', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6))),
    ]),
  );

  Widget _buildInput() => Container(
    color: AppColors.background,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      // Reply preview
      if (_replyingTo != null)
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(children: [
            Container(width: 3, height: 36, decoration: BoxDecoration(
                color: AppColors.primary, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _replyingTo!.userId == _myId ? 'Вы' :
                    (_replyingTo!.user?.displayName.isNotEmpty == true
                        ? _replyingTo!.user!.displayName
                        : _replyingTo!.user?.username ?? 'Пользователь'),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
              ),
              Text(
                _replyingTo!.content.isNotEmpty ? _replyingTo!.content
                    : _replyingTo!.fileType == 'IMAGE' ? '🖼️ Фото'
                    : _replyingTo!.fileType == 'VIDEO' ? '🎥 Видео'
                    : _replyingTo!.fileType == 'AUDIO' ? '🎤 Голосовое'
                    : '📎 Файл',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
              ),
            ])),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: Colors.white54),
              onPressed: _cancelReply,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
        ),
      // Edit preview
      if (_editingMsg != null)
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(children: [
            Container(width: 3, height: 36, decoration: BoxDecoration(
                color: Colors.orange, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Редактирование', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange)),
              Text(_editingMsg!.content, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
            ])),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: Colors.white54),
              onPressed: _cancelEdit,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(children: [
          GestureDetector(
            onTap: _showAttachMenu,
            child: Container(
              width: 46, height: 46,
              decoration: BoxDecoration(color: const Color(0xFF2D3542), shape: BoxShape.circle),
              child: const Icon(Icons.attach_file_rounded, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(
            decoration: BoxDecoration(color: const Color(0xFF2D3542), borderRadius: BorderRadius.circular(30)),
            child: Row(children: [
              const SizedBox(width: 20),
              Expanded(child: TextField(
                controller: _ctrl,
                focusNode: _focusNode,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                onChanged: _onTextChanged,
                decoration: InputDecoration(
                  hintText: 'Сообщение...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
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
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 46, height: 46,
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
            ),
          ),
        ]),
      ),
    ]),
  );

  Widget _buildReadOnly() => Container(
    padding: const EdgeInsets.all(16),
    color: AppColors.background,
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.muted),
      const SizedBox(width: 6),
      Text('Только администраторы могут писать',
          style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6))),
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
        color: AppColors.surfaceAlt, // white/8
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(_label,
          style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
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
  final void Function(String reactionKey)? onReactionTap;

  const _MessageBubble({
    required this.msg, required this.isMe, required this.showAvatar,
    required this.showName, required this.myId, required this.isPrivate,
    required this.onLongPress, this.onReactionTap,
  });

  static const _reactionEmoji = {
    'heart': '❤️', 'like': '👍', 'laugh': '😂',
    'wow': '😮',   'sad': '😢',  'angry': '😡',
  };

  @override
  Widget build(BuildContext context) {
    final hasReactions = msg.reactions != null &&
        msg.reactions!.entries.any((e) => (e.value as List?)?.isNotEmpty == true);

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

          Flexible(child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onLongPress: onLongPress,
                child: Container(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.70),
                  decoration: BoxDecoration(
                    color: isMe ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                    border: isMe ? null : Border.all(color: AppColors.border),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Имя (только в группах для чужих)
                    if (showName && msg.user != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 14, right: 14, top: 10, bottom: 2),
                        child: Text(
                          msg.user!.displayName.isNotEmpty ? msg.user!.displayName : msg.user!.username,
                          style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.secondary,
                          ),
                        ),
                      ),

                    // Reply-цитата
                    if (msg.replyTo != null) _buildReplyQuote(msg.replyTo!),

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
                          if (msg.updatedAt != null &&
                              msg.updatedAt!.difference(msg.createdAt).inMilliseconds > 2000)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(Icons.edit, size: 12,
                                  color: Colors.white.withValues(alpha: 0.3)),
                            ),
                          Text(
                            DateFormat('HH:mm').format(msg.createdAt),
                            style: TextStyle(fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.6)),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            _buildReadStatus(),
                          ],
                        ],
                      ),
                    ),
                  ]),
                ),
              ),

              // Реакции под пузырём
              if (hasReactions) _buildReactions(),
            ],
          )),

          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildReplyQuote(Message replyTo) {
    final name = replyTo.userId == myId ? 'Вы'
        : (replyTo.user?.displayName.isNotEmpty == true
            ? replyTo.user!.displayName
            : replyTo.user?.username ?? 'Пользователь');
    final content = replyTo.content.isNotEmpty ? replyTo.content
        : replyTo.fileType == 'IMAGE' ? '🖼️ Фото'
        : replyTo.fileType == 'VIDEO' ? '🎥 Видео'
        : replyTo.fileType == 'AUDIO' ? '🎤 Голосовое'
        : '📎 Файл';

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            color: AppColors.secondary)),
        const SizedBox(height: 2),
        Text(content, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
      ]),
    );
  }

  Widget _buildReactions() {
    final entries = msg.reactions!.entries
        .where((e) => (e.value as List?)?.isNotEmpty == true)
        .toList();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 4, runSpacing: 4,
        children: entries.map((e) {
          final users = (e.value as List).map((u) => u.toString()).toList();
          final emoji = _reactionEmoji[e.key] ?? e.key;
          final iMine = users.contains(myId);
          return GestureDetector(
            onTap: () => onReactionTap?.call(e.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: iMine
                    ? AppColors.primary.withValues(alpha: 0.3)
                    : AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: iMine
                      ? AppColors.primary.withValues(alpha: 0.6)
                      : AppColors.border,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(emoji, style: const TextStyle(fontSize: 14)),
                if (users.length > 1) ...[
                  const SizedBox(width: 4),
                  Text('${users.length}',
                      style: const TextStyle(fontSize: 12, color: Colors.white,
                          fontWeight: FontWeight.w600)),
                ],
              ]),
            ),
          );
        }).toList(),
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
        color: isRead ? Colors.white : Colors.white.withValues(alpha: 0.4),
      );
    } else {
      // Группа: галочка + число прочитавших
      final count = msg.readReceipts.where((r) => r.userId != myId).length;
      if (count == 0) {
        return Icon(Icons.done_rounded, size: 10,
            color: Colors.white.withValues(alpha: 0.6));
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
        : CircleAvatar(radius: 20, backgroundColor: const Color(0x206C3EF4),
            child: Text(name[0].toUpperCase(),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: AppColors.primary)));
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
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16)),
          child: Icon(icon, color: color, size: 26)),
      const SizedBox(height: 4),
      Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.5))),
    ]),
  );
}


// ─── Typing Indicator ────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  final List<String> names;
  const _TypingIndicator({required this.names});
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final label = widget.names.length == 1
        ? '${widget.names[0]} печатает...'
        : '${widget.names.join(', ')} печатают...';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      color: AppColors.background,
      child: Row(children: [
        FadeTransition(
          opacity: _anim,
          child: Row(children: List.generate(3, (i) => Container(
            width: 6, height: 6, margin: const EdgeInsets.only(right: 3),
            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
          ))),
        ),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
      ]),
    );
  }
}



