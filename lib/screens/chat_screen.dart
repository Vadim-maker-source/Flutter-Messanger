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
import '../main.dart' show AppColors, lockCallSlot, unlockCallSlot;
import '../widgets/colored_avatar.dart';
import 'call_screen.dart';
import 'user_profile_screen.dart';
import 'chat_info_screen.dart';
import 'chat_picker_screen.dart';

import 'media_recorder.dart';
import 'media_widgets.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';


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
  final Set<String> _pendingContents = {}; // тексты сообщений в процессе отправки (для дедупликации)

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

  // Emoji & input state
  bool _showEmoji = false;
  bool _hasText = false;

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
        // Дедупликация: проверяем и по _sentIds, и по уже существующим в списке,
        // и по pending-контенту (если Socket.io прилетел раньше HTTP-ответа)
        if (_sentIds.remove(msg.id)) return;
        if (_messages.any((m) => m.id == msg.id)) return;
        if (msg.userId == _myId && _pendingContents.contains(msg.content)) {
          _sentIds.add(msg.id); // запомним id чтобы не добавить повторно из HTTP-ответа
          _pendingContents.remove(msg.content);
          return;
        }
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
                _messages[i] = msg.copyWith(
                  readReceipts: [
                    ...msg.readReceipts,
                    ReadReceipt(userId: _myId ?? '', readAt: DateTime.now()),
                  ],
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
            _messages[i] = _messages[i].copyWith(reactions: reactions);
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
    setState(() => _hasText = false);
    _stopTyping();
    final replyId = _replyingTo?.id;
    setState(() => _replyingTo = null);
    // Помечаем что ожидаем сообщение с таким текстом — если Socket.io
    // доставит его раньше чем вернётся HTTP-ответ, дедупликация сработает.
    _pendingContents.add(text);
    final msg = await _api.sendMessage(widget.chat.id, text, replyToId: replyId);
    _pendingContents.remove(text);
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
    final hasText = value.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
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

  Future<void> _showForwardDialog(Message msg) async {
    final count = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPickerScreen(
          forwardMessageId: msg.id,
          excludeChatId: widget.chat.id,
        ),
      ),
    );
    if (!mounted) return;
    if (count != null && count > 0) {
      // Снек-уведомление уже показано внутри ChatPickerScreen.
      // Здесь можно добавить какую-то реакцию, например анимацию.
    }
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
      if (i != -1) {
        _messages[i] = msg.copyWith(content: text, updatedAt: DateTime.now());
      }
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
      body: Container(
        // Фон чата — тёмно-синий как в Telegram dark theme
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1D2633),  // тёмно-синий (Telegram-стиль)
              Color(0xFF1D2633),  // чуть темнее к низу
            ],
          ),
        ),
        child: Column(children: [
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
        if (_showEmoji)
          SizedBox(
            height: 260,
            child: EmojiPicker(
              onEmojiSelected: (_, emoji) {
                _ctrl.text += emoji.emoji;
                _ctrl.selection = TextSelection.fromPosition(
                    TextPosition(offset: _ctrl.text.length));
                if (!_hasText) setState(() => _hasText = true);
              },
              config: Config(
                height: 260,
                emojiViewConfig: EmojiViewConfig(
                  backgroundColor: const Color(0xFF1D2633),
                  columns: 8,
                  emojiSizeMax: 28,
                ),
                categoryViewConfig: const CategoryViewConfig(
                  backgroundColor: Color(0xFF1D2633),
                  iconColorSelected: Color(0xFF7166D8),
                  indicatorColor: Color(0xFF7166D8),
                  iconColor: Colors.white38,
                ),
                searchViewConfig: const SearchViewConfig(
                  backgroundColor: Color(0xFF1D2633),
                  buttonIconColor: Colors.white38,
                ),
              ),
            ),
          ),
      ])),
    );
  }

  void _openChatInfo() {
    if (widget.chat.type == 'PRIVATE') {
      // Для приватного чата — открываем профиль собеседника
      final partnerId = widget.chat.partnerId;
      if (partnerId != null && partnerId.isNotEmpty) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => UserProfileScreen(
            userId: partnerId,
            displayName: widget.chat.title,
            avatarUrl: widget.chat.imageUrl,
          ),
        ));
      }
    } else {
      // Для группы/канала — открываем инфо чата
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatInfoScreen(chat: widget.chat),
      ));
    }
  }

  Future<void> _startCall(String type) async {
    // Lock slot immediately so the Pusher outgoing-call echo is ignored
    lockCallSlot();
    final data = await _api.startCall(widget.chat.id, type);
    if (data == null) {
      unlockCallSlot();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось начать звонок')),
        );
      }
      return;
    }
    if (!mounted) { unlockCallSlot(); return; }
    final callId = data['callId'] as String? ?? '';
    // Open CallScreen directly — don't wait for Pusher outgoing-call
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CallScreen(
        callId: callId,
        chatId: widget.chat.id,
        callType: type,
        isIncoming: false,
        callerName: '',
        chatName: widget.chat.title,
      ),
    )).then((_) => unlockCallSlot());
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
      title: GestureDetector(
        onTap: _openChatInfo,
        child: Row(children: [
        // Аватар
        Stack(children: [
          ColoredAvatar(
            imageUrl: widget.chat.imageUrl,
            title: widget.chat.title,
            size: 44,
          ),
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
      ])),
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
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
    decoration: const BoxDecoration(color: Color(0xFF1D2633)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      // Reply preview
      if (_replyingTo != null)
        Container(
          margin: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF2D3542),
            borderRadius: BorderRadius.circular(14),
            border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
          ),
          child: Row(children: [
            Icon(Icons.reply_rounded, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
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
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
              ),
            ])),
            IconButton(
              icon: Icon(Icons.close_rounded, size: 18, color: Colors.white.withValues(alpha: 0.5)),
              onPressed: _cancelReply,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ]),
        ),
      // Edit preview
      if (_editingMsg != null)
        Container(
          margin: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF2D3542),
            borderRadius: BorderRadius.circular(14),
            border: const Border(left: BorderSide(color: Color(0xFFFB923C), width: 3)),
          ),
          child: Row(children: [
            const Icon(Icons.edit_rounded, size: 16, color: Color(0xFFFB923C)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Редактирование',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFFB923C))),
              Text(_editingMsg!.content,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
            ])),
            IconButton(
              icon: Icon(Icons.close_rounded, size: 18, color: Colors.white.withValues(alpha: 0.5)),
              onPressed: _cancelEdit,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ]),
        ),
      // Input row — единая капсула с инлайн-кнопками
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        // Pill-капсула с emoji внутри + текст + скрепка внутри
        Expanded(child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          decoration: BoxDecoration(
            color: const Color(0xFF2D3542),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            // Emoji button (внутри капсулы слева)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 7, top: 7),
              child: _IconRoundBtn(
                icon: _showEmoji ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined,
                onTap: () {
                  if (_showEmoji) {
                    setState(() => _showEmoji = false);
                    _focusNode.requestFocus();
                  } else {
                    _focusNode.unfocus();
                    setState(() => _showEmoji = true);
                  }
                },
              ),
            ),
            // Text field
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextField(
                controller: _ctrl,
                focusNode: _focusNode,
                maxLines: 5,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3),
                onChanged: _onTextChanged,
                onTap: () {
                  if (_showEmoji) setState(() => _showEmoji = false);
                },
                decoration: InputDecoration(
                  hintText: 'Сообщение',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 15),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  isDense: true,
                ),
                onSubmitted: (_) => _send(),
              ),
            )),
            // Attach (внутри капсулы справа)
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 7, top: 7),
              child: _IconRoundBtn(
                icon: Icons.attach_file_rounded,
                rotate: -0.6,
                onTap: _showAttachMenu,
              ),
            ),
          ]),
        )),
        const SizedBox(width: 8),
        // Send / Mic — отдельная фиолетовая кнопка справа
        Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: GestureDetector(
              key: ValueKey(_hasText),
              onTap: _hasText ? _send : null,
              child: Container(
                width: 46, height: 46,
                decoration: const BoxDecoration(
                  color: Color(0xFF7166D8),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _hasText ? Icons.send_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ]),
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
                    color: isMe ? const Color(0xFF7166D8) : const Color(0xFF2D3542),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 6, offset: const Offset(0, 2))],
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

                    // Бейдж «Переслано из ...» (только для пересланных сообщений)
                    if (msg.isForwarded) _buildForwardedBadge(context),

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
                                  color: isMe ? const Color(0xFFB8B0F0) : Colors.white.withValues(alpha: 0.3)),
                            ),
                          Text(
                            DateFormat('HH:mm').format(msg.createdAt),
                            style: TextStyle(fontSize: 12,
                                color: isMe ? const Color(0xFFB8B0F0) : Colors.white.withValues(alpha: 0.5)),
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

  Widget _buildForwardedBadge(BuildContext context) {
    final source = msg.forwardedFromChatType == 'PRIVATE'
        ? (msg.forwardedFromUserName ?? msg.forwardedFromChatName ?? 'Неизвестно')
        : (msg.forwardedFromChatName ?? msg.forwardedFromUserName ?? 'Неизвестно');

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.forward_rounded,
            size: 12, color: AppColors.secondary.withValues(alpha: 0.8)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'Переслано из $source',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: AppColors.secondary.withValues(alpha: 0.85),
            ),
          ),
        ),
      ]),
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
        case 'IMAGE': return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ImageMessage(url: msg.fileUrl!));
        case 'VIDEO': return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: VideoMessage(url: msg.fileUrl!));
        case 'ROUND': return RoundVideoMessage(url: msg.fileUrl!);
        case 'AUDIO': return AudioMessage(url: msg.fileUrl!, isMe: isMe);
        default: return _buildFileCard();
      }
    }
    if (msg.content.isNotEmpty) {
      return Text(msg.content,
          style: const TextStyle(fontSize: 15, color: Colors.white, height: 1.4));
    }
    return const SizedBox.shrink();
  }

  /// Карточка файла — использует FileMessage из media_widgets (с реальным скачиванием).
  Widget _buildFileCard() {
    return FileMessage(
      url: msg.fileUrl!,
      fileName: msg.fileName ?? msg.content,
      isMe: isMe,
    );
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
        : CircleAvatar(radius: 20, backgroundColor: const Color(0x202AABEE),
            child: Text(name[0].toUpperCase(),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: Color(0xFF7166D8))));
  }
}

// ─── Кнопка прикрепления ─────────────────────────────────────────────────────

class _IconRoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double rotate;
  const _IconRoundBtn({required this.icon, required this.onTap, this.rotate = 0});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 32, height: 32,
          child: Center(
            child: Transform.rotate(
              angle: rotate,
              child: Icon(icon, size: 22, color: Colors.white.withValues(alpha: 0.55)),
            ),
          ),
        ),
      ),
    );
  }
}

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



