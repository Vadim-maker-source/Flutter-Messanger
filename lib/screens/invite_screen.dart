import 'package:flutter/material.dart';
import '../main.dart';
import '../models/chat.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';
import 'server_channels_screen.dart';

/// Экран обработки invite-ссылки.
///
/// Загружает информацию о приглашении, показывает превью (иконку + название
/// + количество участников) и кнопку «Присоединиться». После успешного
/// присоединения переходит в чат или к экрану каналов сервера.
class InviteScreen extends StatefulWidget {
  final String code;
  const InviteScreen({super.key, required this.code});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _info;
  bool _loading = true;
  bool _joining = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await _api.getInviteInfo(widget.code);
    if (!mounted) return;
    setState(() {
      _info = info;
      _loading = false;
      if (info == null) _error = 'Приглашение недействительно или истекло';
    });
  }

  Future<void> _join() async {
    setState(() {
      _joining = true;
      _error = null;
    });
    final result = await _api.joinByInvite(widget.code);
    if (!mounted) return;

    if (result?['success'] == true) {
      final type = result!['type'] as String?;
      final targetId = result['targetId'] as String?;

      if (type == 'CHAT' && targetId != null) {
        // Открываем чат
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              chat: Chat(
                id: targetId,
                title: _info?['target']?['name'] ?? '',
                imageUrl: _info?['target']?['imageUrl'],
                type: _info?['target']?['type'] ?? 'GROUP',
              ),
            ),
          ),
        );
      } else if (type == 'SERVER' && targetId != null) {
        // Открываем экран каналов сервера
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ServerChannelsScreen(
              server: {
                'id': targetId,
                'name': _info?['target']?['name'] ?? '',
                'imageUrl': _info?['target']?['imageUrl'],
              },
            ),
          ),
        );
      } else {
        Navigator.pop(context);
      }
    } else {
      setState(() {
        _joining = false;
        _error = result?['error'] as String? ?? 'Не удалось присоединиться';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded,
              color: Colors.white.withValues(alpha: 0.7)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Приглашение',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: _loading
              ? const CircularProgressIndicator(color: AppColors.primary)
              : _info == null
                  ? _ErrorView(message: _error ?? 'Ошибка')
                  : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final target = _info!['target'] as Map<String, dynamic>?;
    final type = (_info!['type'] as String?) ?? 'CHAT';
    final isServer = type == 'SERVER';
    final memberCount = _info!['memberCount'] as int? ?? 0;
    final name = target?['name'] as String? ?? 'Без названия';
    final imageUrl = target?['imageUrl'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Avatar
            Center(
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1F1F26),
                ),
                clipBehavior: Clip.antiAlias,
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(imageUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _initialAvatar(name))
                    : _initialAvatar(name),
              ),
            ),
            const SizedBox(height: 18),

            // Type label
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    isServer ? Icons.dns_rounded : Icons.tag_rounded,
                    size: 12,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isServer ? 'Сервер' : 'Чат',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),

            // Name
            Text(name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(height: 6),
            Text('$memberCount участников',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: Colors.white.withValues(alpha: 0.5))),

            const SizedBox(height: 32),

            // Description
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1F1F26),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.group_add_rounded,
                      color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isServer
                          ? 'Вас пригласили на сервер'
                          : 'Вас пригласили в чат',
                      style: const TextStyle(
                          fontSize: 13.5,
                          color: Colors.white,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text('Присоединившись, вы получите доступ ко всем сообщениям',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.4))),
                  ],
                )),
              ]),
            ),

            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFFEF4444), fontSize: 13)),
              ),
            ],

            const SizedBox(height: 24),

            // Action button
            Material(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: _joining ? null : _join,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  child: _joining
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Присоединиться',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Отмена',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.5))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _initialAvatar(String name) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      color: AppColors.primary.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Text(letter,
          style: const TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w700,
              color: AppColors.primary)),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFEF4444).withValues(alpha: 0.12),
            ),
            child: const Icon(Icons.link_off_rounded,
                color: Color(0xFFEF4444), size: 28),
          ),
          const SizedBox(height: 16),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
          const SizedBox(height: 6),
          Text('Попросите автора прислать новое приглашение',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: Colors.white.withValues(alpha: 0.4))),
        ],
      ),
    );
  }
}
