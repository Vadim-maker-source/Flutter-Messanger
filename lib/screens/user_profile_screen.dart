import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../main.dart';
import '../models/chat.dart';
import '../services/api_service.dart';
import '../widgets/colored_avatar.dart';
import 'chat_screen.dart';
import 'call_screen.dart';

/// Профиль другого пользователя — точная копия веб-версии
/// (`app/(root)/profile/[type]/page.tsx`).
///
/// Структура:
///   • Sticky header «Профиль» с back-кнопкой;
///   • Большой аватар + display name + индикатор онлайна + last seen;
///   • Ряд квадратных кнопок: Чат, Звонок, Видео, Звук, Ещё (popup);
///   • Табы: Информация | Общие чаты (N) | Медиа;
///   • Information tab: @username, bio, соцссылки;
///   • Mutual chats: цветные иконки (PRIVATE/GROUP), счётчики, last message;
///   • Media: 4 вложенных таба (Фото / Видео / Файлы / Аудио),
///     грид для фото/видео, список для файлов/аудио, fullscreen-просмотр.
class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String? displayName;
  final String? avatarUrl;

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.displayName,
    this.avatarUrl,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  static const _violet = Color(0xFF7166D8); // акцент из веб-версии

  final _api = ApiService();

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _media; // {photos, videos, files, audio}
  bool _loading = true;
  bool _loadingMedia = false;
  bool _isBlockLoading = false;
  bool _isAudioLoading = false;
  bool _isVideoLoading = false;

  /// 0 = Информация, 1 = Общие чаты, 2 = Медиа
  int _tab = 0;

  /// 0=Фото, 1=Видео, 2=Файлы, 3=Аудио
  int _mediaTab = 0;

  String? _existingChatId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await _api.getUserProfile(widget.userId);
    if (!mounted) return;
    setState(() {
      _profile = res;
      _loading = false;
    });
    // Проверим существующий приватный чат, чтобы навигировать без задержки
    // при тапе на «Чат»/«Звонок»/«Видео».
    _ensurePrivateChatId();
  }

  Future<String?> _ensurePrivateChatId() async {
    if (_existingChatId != null) return _existingChatId;
    final chat = await _api.getOrCreatePrivateChat(widget.userId);
    if (chat != null) _existingChatId = chat['id'] as String?;
    return _existingChatId;
  }

  Future<void> _loadMedia() async {
    if (_media != null || _loadingMedia) return;
    setState(() => _loadingMedia = true);
    final m = await _api.getUserMediaFiles(widget.userId);
    if (!mounted) return;
    setState(() {
      _media = m ?? {'photos': [], 'videos': [], 'files': [], 'audio': []};
      _loadingMedia = false;
    });
  }

  // ─── Getters / formatters ────────────────────────────────────────────────
  String get _name =>
      _profile?['displayName'] as String? ??
      widget.displayName ??
      'Пользователь';
  String? get _username => _profile?['username'] as String?;
  String? get _avatar => _profile?['avatarUrl'] as String? ?? widget.avatarUrl;
  String? get _bio => _profile?['bio'] as String?;
  bool get _isOnline => _profile?['isOnline'] == true;
  String? get _status => _profile?['status'] as String?;
  bool get _isSelf => _profile?['isSelf'] == true;
  bool get _iBlockedThem => _profile?['iBlockedThem'] == true;
  bool get _canSeeExtras => _profile?['canSeeProfileExtras'] != false;
  Map<String, dynamic>? get _socialLinks =>
      (_profile?['socialLinks'] as Map?)?.cast<String, dynamic>();

  String _formatLastSeen() {
    final ls = _profile?['lastSeen'];
    if (ls == null) return 'был(а) недавно';
    try {
      final dt = DateTime.parse(ls.toString()).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'только что';
      if (diff.inMinutes < 60) return 'был(а) ${diff.inMinutes} мин. назад';
      if (diff.inHours < 24) return 'был(а) ${diff.inHours} ч. назад';
      if (diff.inDays < 7) return 'был(а) ${diff.inDays} д. назад';
      return 'был(а) ${DateFormat('d MMM', 'ru').format(dt)}';
    } catch (_) {
      return 'был(а) недавно';
    }
  }

  String _relTime(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'только что';
      if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
      if (diff.inHours < 24) return '${diff.inHours} ч назад';
      return '${diff.inDays} д назад';
    } catch (_) {
      return '';
    }
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return DateFormat('d MMMM y', 'ru').format(dt);
    } catch (_) {
      return '';
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 32, height: 32,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary),
              ),
            )
          : _profile == null
              ? _buildNotFound()
              : _buildContent(),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_outline,
              size: 64, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          const Text('Пользователь не найден',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('Возможно, аккаунт был удалён',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Вернуться назад'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _buildProfileHeader(),
              _buildTabsBar(),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildTabContent(),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Sticky header ───────────────────────────────────────────────────────
  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF121214).withValues(alpha: 0.5),
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back,
                  color: Colors.white.withValues(alpha: 0.6)),
              onPressed: () => Navigator.pop(context),
            ),
            const Expanded(
              child: Text('Профиль',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  // ─── Profile header (avatar + name + actions) ────────────────────────────
  Widget _buildProfileHeader() {
    // Determine status color & text (как web: online=зелёный, away=жёлтый, busy=красный, offline=серый)
    Color statusColor;
    String statusText;
    if (_isOnline) {
      statusColor = const Color(0xFF22C55E);
      statusText = 'В сети';
    } else {
      switch (_status) {
        case 'away':
          statusColor = const Color(0xFFEAB308);
          statusText = 'Отошёл';
          break;
        case 'busy':
          statusColor = const Color(0xFFEF4444);
          statusText = 'Не беспокоить';
          break;
        default:
          statusColor = const Color(0xFF6B7280);
          statusText = 'Не в сети';
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        children: [
          // Avatar with online dot
          Stack(
            children: [
              Container(
                width: 112, height: 112,
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
                  child: _avatar != null && _avatar!.isNotEmpty
                      ? Image.network(_avatar!, fit: BoxFit.cover,
                          errorBuilder: (_, e, s) => _avatarFallback())
                      : _avatarFallback(),
                ),
              ),
              Positioned(
                bottom: 4, right: 4,
                child: _OnlineDot(color: statusColor, pulse: _isOnline),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Name + «Это вы»
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(_name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold)),
              if (_isSelf)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('Это вы',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primary
                              .withBlue(255)
                              .withGreen(140))),
                ),
            ],
          ),
          // Status / Last seen (как в web: online→"В сети", away→"Отошёл", busy→"Не беспокоить", offline+lastSeen→lastSeen)
          const SizedBox(height: 6),
          if (_isOnline)
            Text(statusText,
                style: const TextStyle(fontSize: 14, color: Color(0xFF22C55E)))
          else ...[
            Text(statusText,
                style: TextStyle(
                    fontSize: 14,
                    color: statusColor.withValues(alpha: 0.9))),
            if (_profile?['lastSeen'] != null) ...[
              const SizedBox(height: 2),
              Text(_formatLastSeen(),
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.4))),
            ],
          ],
          // Action buttons
          if (!_isSelf) ...[
            const SizedBox(height: 20),
            _buildActions(),
          ],
        ],
      ),
    );
  }

  Widget _avatarFallback() {
    return Container(
      alignment: Alignment.center,
      child: Text(
        _name.isNotEmpty ? _name[0].toUpperCase() : '?',
        style: const TextStyle(
            color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ─── Action row ──────────────────────────────────────────────────────────
  Widget _buildActions() {
    return Row(
      children: [
        Expanded(child: _ActionBtn(
            icon: Icons.chat_bubble_outline,
            label: 'Чат',
            onTap: _openChat)),
        const SizedBox(width: 8),
        Expanded(child: _ActionBtn(
            icon: Icons.phone_outlined,
            label: 'Звонок',
            loading: _isAudioLoading,
            onTap: () => _startCall('audio'))),
        const SizedBox(width: 8),
        Expanded(child: _ActionBtn(
            icon: Icons.videocam_outlined,
            label: 'Видео',
            loading: _isVideoLoading,
            onTap: () => _startCall('video'))),
        const SizedBox(width: 8),
        Expanded(child: _ActionBtn(
            icon: Icons.volume_up_outlined,
            label: 'Звук',
            onTap: _toggleMute)),
        const SizedBox(width: 8),
        Expanded(child: _ActionBtn(
            icon: Icons.more_vert,
            label: 'Ещё',
            onTap: _showMoreMenu)),
      ],
    );
  }

  // ─── Tabs ────────────────────────────────────────────────────────────────
  Widget _buildTabsBar() {
    final mutualCount =
        ((_profile?['mutualChats'] as List?) ?? []).length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
              bottom:
                  BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        ),
        child: Row(
          children: [
            _TabBtn(
              label: 'Информация',
              active: _tab == 0,
              onTap: () => setState(() => _tab = 0),
            ),
            _TabBtn(
              label: mutualCount > 0
                  ? 'Общие чаты ($mutualCount)'
                  : 'Общие чаты',
              active: _tab == 1,
              onTap: () => setState(() => _tab = 1),
            ),
            if (!_isSelf)
              _TabBtn(
                label: 'Медиа',
                active: _tab == 2,
                onTap: () {
                  setState(() => _tab = 2);
                  _loadMedia();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    // Анимированное переключение табов (как `AnimatePresence` в web)
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: KeyedSubtree(
        key: ValueKey(_tab),
        child: switch (_tab) {
          1 => _buildMutualTab(),
          2 => _buildMediaTab(),
          _ => _buildInfoTab(),
        },
      ),
    );
  }

  // ─── Info tab ────────────────────────────────────────────────────────────
  Widget _buildInfoTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          icon: Icons.tag,
          title: 'Имя пользователя',
          child: Text(
            '@${_username ?? ''}',
            style: const TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        if (_bio != null && _bio!.isNotEmpty && _canSeeExtras) ...[
          const SizedBox(height: 12),
          _Card(
            icon: Icons.person_outline,
            title: 'О себе',
            child: SelectableText(_bio!,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 15,
                    height: 1.5)),
          ),
        ],
        if (_socialLinks != null) ...[
          const SizedBox(height: 12),
          _Card(
            icon: Icons.link,
            title: 'Соцсети и ссылки',
            child: _buildSocialLinks(_socialLinks!),
          ),
        ],
        // Статистика (как в web-версии)
        if (_profile?['stats'] != null || _profile?['createdAt'] != null) ...[
          const SizedBox(height: 12),
          _Card(
            icon: Icons.trending_up,
            title: 'Статистика',
            child: _buildStats(),
          ),
        ],
      ],
    );
  }

  Widget _buildStats() {
    final stats = _profile?['stats'] as Map<String, dynamic>?;
    final messagesCount = stats?['messagesCount'] as int? ?? 0;
    final chatsCount = stats?['chatsCount'] as int? ?? 0;
    final createdAt = _profile?['createdAt'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _StatItem(
              icon: Icons.mail_outline,
              label: 'Сообщений',
              value: '$messagesCount'),
          const SizedBox(width: 24),
          _StatItem(
              icon: Icons.forum_outlined,
              label: 'Чатов',
              value: '$chatsCount'),
        ]),
        if (createdAt != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.calendar_today,
                size: 14, color: Colors.white.withValues(alpha: 0.4)),
            const SizedBox(width: 6),
            Text('В мессенджере с ${_formatDate(createdAt)}',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.5))),
          ]),
        ],
      ],
    );
  }

  Widget _buildSocialLinks(Map<String, dynamic> links) {
    final items = <Widget>[];
    void add(String name, String? url) {
      if (url == null || url.isEmpty) return;
      items.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text('$name: ',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7), fontSize: 15)),
          Expanded(
            child: GestureDetector(
              onTap: () =>
                  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              child: Text(url,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 15,
                      decoration: TextDecoration.underline)),
            ),
          ),
        ]),
      ));
    }

    add('Telegram', links['telegram'] as String?);
    add('VK', links['vk'] as String?);
    add('GitHub', links['github'] as String?);
    add('Сайт', links['website'] as String?);

    if (items.isEmpty) {
      return Text('Пользователь не добавил ссылки.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4)));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: items);
  }

  // ─── Mutual chats tab ────────────────────────────────────────────────────
  Widget _buildMutualTab() {
    final list = (_profile?['mutualChats'] as List?) ?? [];

    return _Card(
      icon: Icons.forum_outlined,
      title: 'Общие чаты',
      child: list.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Нет общих чатов с этим пользователем',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.6))),
              ),
            )
          : Column(
              children: list.map<Widget>((c) {
                final chat = Map<String, dynamic>.from(c as Map);
                final chatType = chat['type'] as String? ?? 'GROUP';
                return _MutualChatTile(
                  chat: chat,
                  relTime: _relTime,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          chat: Chat(
                            id: chat['id'] ?? '',
                            title: chat['name'] ?? '',
                            type: chatType,
                            imageUrl: chat['imageUrl'] as String?,
                            partnerId: chatType == 'PRIVATE' ? widget.userId : null,
                          ),
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
            ),
    );
  }

  // ─── Media tab ───────────────────────────────────────────────────────────
  Widget _buildMediaTab() {
    return Column(
      children: [
        _buildMediaTabsBar(),
        const SizedBox(height: 12),
        _Card(
          icon: null,
          title: null,
          child: _loadingMedia
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: SizedBox(
                      width: 28, height: 28,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    ),
                  ),
                )
              : _buildMediaContent(),
        ),
      ],
    );
  }

  Widget _buildMediaTabsBar() {
    final tabs = [
      (Icons.image_outlined, 'Фото',
          (_media?['photos'] as List?)?.length ?? 0),
      (Icons.videocam_outlined, 'Видео',
          (_media?['videos'] as List?)?.length ?? 0),
      (Icons.description_outlined, 'Файлы',
          (_media?['files'] as List?)?.length ?? 0),
      (Icons.audiotrack, 'Аудио',
          (_media?['audio'] as List?)?.length ?? 0),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final (icon, label, count) = tabs[i];
          final active = _mediaTab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _mediaTab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.primary.withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon,
                        size: 18,
                        color: active
                            ? _violet
                            : Colors.white.withValues(alpha: 0.6)),
                    const SizedBox(height: 2),
                    FittedBox(
                      child: Text(
                        count > 0 ? '$label ($count)' : label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: active
                                ? _violet
                                : Colors.white.withValues(alpha: 0.6)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildMediaContent() {
    if (_media == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('Откройте вкладку Медиа',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
        ),
      );
    }
    switch (_mediaTab) {
      case 0:
        return _buildPhotoGrid(
            (_media!['photos'] as List?) ?? [], isVideo: false);
      case 1:
        return _buildPhotoGrid(
            (_media!['videos'] as List?) ?? [], isVideo: true);
      case 2:
        return _buildFilesList((_media!['files'] as List?) ?? []);
      case 3:
        return _buildAudioList((_media!['audio'] as List?) ?? []);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPhotoGrid(List items, {required bool isVideo}) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(isVideo ? 'Нет видео' : 'Нет фотографий',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final m = Map<String, dynamic>.from(items[i] as Map);
        final url = m['url'] as String? ?? '';
        return GestureDetector(
          onTap: () => _openMediaViewer(items, i, isVideo: isVideo),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, e, s) => Container(
                          color: Colors.white.withValues(alpha: 0.05),
                          child: Icon(Icons.broken_image,
                              color: Colors.white.withValues(alpha: 0.3)),
                        )),
                if (isVideo)
                  Container(
                    color: Colors.black.withValues(alpha: 0.4),
                    child: const Center(
                      child: Icon(Icons.play_arrow,
                          color: Colors.white, size: 36),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilesList(List items) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text('Нет файлов',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
        ),
      );
    }
    return Column(
      children: items.map<Widget>((it) {
        final m = Map<String, dynamic>.from(it as Map);
        final url = m['url'] as String? ?? '';
        return GestureDetector(
          onTap: () =>
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.description_outlined,
                    color: _violet, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m['fileName'] ?? 'Файл',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                    Text(_formatDate(m['createdAt']),
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.4))),
                  ],
                ),
              ),
              Icon(Icons.download,
                  color: Colors.white.withValues(alpha: 0.4), size: 20),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAudioList(List items) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text('Нет аудио',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
        ),
      );
    }
    return Column(
      children: items.map<Widget>((it) {
        final m = Map<String, dynamic>.from(it as Map);
        final url = m['url'] as String? ?? '';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.audiotrack, color: _violet, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m['fileName'] ?? 'Аудио',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  Text(_formatDate(m['createdAt']),
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.4))),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.play_circle_outline, color: _violet),
              onPressed: () => launchUrl(Uri.parse(url),
                  mode: LaunchMode.externalApplication),
            ),
          ]),
        );
      }).toList(),
    );
  }

  // ─── Actions ─────────────────────────────────────────────────────────────
  Future<void> _openChat() async {
    final id = await _ensurePrivateChatId();
    if (id == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chat: Chat(
            id: id,
            title: _name,
            type: 'PRIVATE',
            imageUrl: _avatar,
            partnerId: widget.userId,
          ),
        ),
      ),
    );
  }

  Future<void> _startCall(String type) async {
    setState(() {
      if (type == 'audio') _isAudioLoading = true;
      if (type == 'video') _isVideoLoading = true;
    });
    final id = await _ensurePrivateChatId();
    if (id == null) {
      if (mounted) {
        setState(() {
          _isAudioLoading = false;
          _isVideoLoading = false;
        });
      }
      return;
    }
    lockCallSlot();
    final data = await _api.startCall(id, type);
    if (!mounted) return;
    setState(() {
      _isAudioLoading = false;
      _isVideoLoading = false;
    });
    if (data == null) {
      unlockCallSlot();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: data['callId'] ?? '',
          chatId: id,
          callType: type,
          isIncoming: false,
          callerName: '',
          chatName: _name,
        ),
      ),
    ).then((_) => unlockCallSlot());
  }

  void _toggleMute() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Уведомления для этого чата (скоро)'),
      duration: Duration(seconds: 2),
    ));
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1F),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 36, height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2))),
            ListTile(
              leading: const Icon(Icons.link, color: _violet),
              title: const Text('Скопировать ссылку',
                  style: TextStyle(color: Colors.white)),
              onTap: _copyProfileLink,
            ),
            ListTile(
              leading: Icon(_iBlockedThem ? Icons.lock_open : Icons.block,
                  color: Colors.redAccent),
              title: Text(_iBlockedThem ? 'Разблокировать' : 'Заблокировать',
                  style: const TextStyle(color: Colors.redAccent)),
              enabled: !_isBlockLoading,
              onTap: _toggleBlock,
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: Colors.redAccent),
              title: const Text('Удалить чат',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Удаление чата (скоро)'),
                ));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _copyProfileLink() async {
    Navigator.pop(context);
    // HTTPS-ссылка — распознаётся как кликабельная всеми мессенджерами,
    // соцсетями, поисковиками. Приложение зарегистрировано как обработчик
    // через intent-filter (Android) / universal links (iOS).
    final link = 'https://194.87.201.226/profile/${widget.userId}';
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Ссылка скопирована'),
      duration: Duration(seconds: 2),
    ));
  }

  Future<void> _toggleBlock() async {
    Navigator.pop(context);
    setState(() => _isBlockLoading = true);
    final ok = _iBlockedThem
        ? await _api.unblockUser(widget.userId)
        : await _api.blockUser(widget.userId);
    if (!mounted) return;
    if (ok && _profile != null) {
      _profile!['iBlockedThem'] = !_iBlockedThem;
    }
    setState(() => _isBlockLoading = false);
  }

  // ─── Media viewer ────────────────────────────────────────────────────────
  void _openMediaViewer(List items, int initial, {required bool isVideo}) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _MediaViewer(
        items: items.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        initialIndex: initial,
        isVideo: isVideo,
      ),
    ));
  }
}

// ─── Action button ─────────────────────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool loading;
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Opacity(
        opacity: loading ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              loading
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _UserProfileScreenState._violet),
                    )
                  : Icon(icon,
                      color: _UserProfileScreenState._violet, size: 22),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.8))),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Top tab button (underline) ────────────────────────────────────────────
class _TabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabBtn(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active
                    ? _UserProfileScreenState._violet
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: active
                  ? _UserProfileScreenState._violet
                  : Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Card section ─────────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  final IconData? icon;
  final String? title;
  final Widget child;
  const _Card({this.icon, this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18,
                      color: _UserProfileScreenState._violet),
                  const SizedBox(width: 8),
                ],
                Text(title!,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

// ─── Mutual chat tile ──────────────────────────────────────────────────────
class _MutualChatTile extends StatelessWidget {
  final Map<String, dynamic> chat;
  final VoidCallback onTap;
  final String Function(dynamic) relTime;
  const _MutualChatTile({
    required this.chat,
    required this.onTap,
    required this.relTime,
  });

  @override
  Widget build(BuildContext context) {
    final type = chat['type'] as String? ?? 'GROUP';
    final isPrivate = type == 'PRIVATE';
    final name = chat['name'] as String? ?? '';
    final imageUrl = chat['imageUrl'] as String?;
    final last = chat['lastMessage'] as String?;
    final lastTime = chat['lastMessageTime'];
    final members = chat['membersCount'] ?? 0;
    final messages = chat['messagesCount'] ?? 0;

    // Иконка по типу: PRIVATE → фиолетовый, GROUP → зелёный (как в web)
    Widget leading;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      leading = ColoredAvatar(imageUrl: imageUrl, title: name, size: 44);
    } else {
      leading = Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isPrivate
              ? AppColors.primary.withValues(alpha: 0.2)
              : const Color(0xFF22C55E).withValues(alpha: 0.2),
        ),
        child: Icon(
          isPrivate ? Icons.person_outline : Icons.group_outlined,
          color: isPrivate ? const Color(0xFFA78BFA) : const Color(0xFF4ADE80),
          size: 22,
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  children: [
                    Text('$members участников',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.4))),
                    Text('•',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.4))),
                    Text('$messages сообщений',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.4))),
                    if (lastTime != null) ...[
                      Text('•',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.4))),
                      Text(relTime(lastTime),
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.4))),
                    ],
                  ],
                ),
                if (last != null && last.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.6))),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.2), size: 20),
        ]),
      ),
    );
  }
}

// ─── Fullscreen media viewer ──────────────────────────────────────────────
class _MediaViewer extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final int initialIndex;
  final bool isVideo;

  const _MediaViewer({
    required this.items,
    required this.initialIndex,
    required this.isVideo,
  });

  @override
  State<_MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<_MediaViewer> {
  late PageController _pc;
  late int _index;
  VideoPlayerController? _videoCtrl;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pc = PageController(initialPage: _index);
    if (widget.isVideo) _initVideo(_index);
  }

  void _initVideo(int i) {
    _videoCtrl?.dispose();
    final url = widget.items[i]['url'] as String? ?? '';
    if (url.isEmpty) return;
    _videoCtrl = VideoPlayerController.networkUrl(Uri.parse(url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _videoCtrl?.play();
      });
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.95),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pc,
            itemCount: widget.items.length,
            onPageChanged: (i) {
              setState(() => _index = i);
              if (widget.isVideo) _initVideo(i);
            },
            itemBuilder: (_, i) {
              final url = widget.items[i]['url'] as String? ?? '';
              if (widget.isVideo) {
                if (i != _index || _videoCtrl == null ||
                    !_videoCtrl!.value.isInitialized) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }
                return Center(
                  child: AspectRatio(
                    aspectRatio: _videoCtrl!.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        VideoPlayer(_videoCtrl!),
                        VideoProgressIndicator(_videoCtrl!,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(
                              playedColor: AppColors.primary,
                              backgroundColor: Colors.white24,
                              bufferedColor: Colors.white38,
                            )),
                      ],
                    ),
                  ),
                );
              }
              return InteractiveViewer(
                child: Center(
                  child: Image.network(url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, e, s) => const Icon(
                            Icons.broken_image,
                            color: Colors.white54, size: 64,
                          )),
                ),
              );
            },
          ),
          // Close button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          // Navigation arrows
          if (widget.items.length > 1) ...[
            Positioned(
              left: 8, top: 0, bottom: 0,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.chevron_left,
                      color: Colors.white, size: 36),
                  onPressed: () {
                    final next =
                        _index > 0 ? _index - 1 : widget.items.length - 1;
                    _pc.animateToPage(next,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOut);
                  },
                ),
              ),
            ),
            Positioned(
              right: 8, top: 0, bottom: 0,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.chevron_right,
                      color: Colors.white, size: 36),
                  onPressed: () {
                    final next =
                        _index < widget.items.length - 1 ? _index + 1 : 0;
                    _pc.animateToPage(next,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOut);
                  },
                ),
              ),
            ),
          ],
          // Counter
          Positioned(
            bottom: 24, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_index + 1} / ${widget.items.length}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stat item (для статистики в info-табе) ─────────────────────────────────
class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatItem(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18,
                color: Colors.white.withValues(alpha: 0.5)),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.4))),
          ],
        ),
      ),
    );
  }
}

// ─── Online dot с pulse-анимацией (как в web-версии) ────────────────────────
class _OnlineDot extends StatefulWidget {
  final Color color;
  final bool pulse;
  const _OnlineDot({required this.color, required this.pulse});

  @override
  State<_OnlineDot> createState() => _OnlineDotState();
}

class _OnlineDotState extends State<_OnlineDot>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  Animation<double>? _anim;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) {
      _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1500),
      )..repeat(reverse: true);
      _anim = Tween<double>(begin: 0.6, end: 1.0).animate(_ctrl!);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.color,
        border: Border.all(color: const Color(0xFF0A0A0C), width: 3),
      ),
    );

    if (_anim == null) return dot;

    return AnimatedBuilder(
      animation: _anim!,
      builder: (_, child) => Opacity(opacity: _anim!.value, child: child),
      child: dot,
    );
  }
}
