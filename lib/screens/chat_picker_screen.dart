import 'dart:io';
import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart';
import '../widgets/colored_avatar.dart';

/// Универсальный экран выбора чатов — используется в двух сценариях:
///
///  1. **Пересылка** существующего сообщения внутри приложения.
///     Передавайте [forwardMessageId] и опционально [excludeChatId]
///     (текущий чат, чтобы скрыть его в списке). Возвращает количество
///     успешно переcланных копий через `Navigator.pop`.
///
///  2. **Шаринг внешнего контента** через системный share-intent.
///     Передавайте [sharedText] и/или [sharedFiles]. Текст и файлы будут
///     отправлены отдельными сообщениями в каждый выбранный чат.
///
/// В обоих случаях:
///   • показывается строка поиска;
///   • можно выбрать несколько чатов (multi-select);
///   • чаты, где у пользователя нет прав писать (CHANNEL без админ-роли),
///     серые и неинтерактивные — точно как `canWrite` фильтр в веб-версии.
class ChatPickerScreen extends StatefulWidget {
  final String? forwardMessageId;
  final String? excludeChatId;
  final String? sharedText;
  final List<File>? sharedFiles;

  const ChatPickerScreen({
    super.key,
    this.forwardMessageId,
    this.excludeChatId,
    this.sharedText,
    this.sharedFiles,
  });

  bool get _isForward => forwardMessageId != null;
  bool get _isShare => sharedText != null || (sharedFiles?.isNotEmpty ?? false);

  @override
  State<ChatPickerScreen> createState() => _ChatPickerScreenState();
}

class _ChatPickerScreenState extends State<ChatPickerScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  bool _sending = false;
  int _progress = 0;
  int _total = 0;

  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await _api.getAvailableChats();
    if (!mounted) return;
    setState(() {
      _all = list
          .where((c) => c['id'] != widget.excludeChatId)
          .toList();
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((c) {
      final title = (c['title'] as String? ?? '').toLowerCase();
      final subtitle = (c['subtitle'] as String? ?? '').toLowerCase();
      return title.contains(q) || subtitle.contains(q);
    }).toList();
  }

  void _toggle(String id, bool canWrite) {
    if (!canWrite) return;
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Future<void> _confirm() async {
    if (_selected.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _progress = 0;
      _total = _selected.length;
    });

    var successCount = 0;
    for (final chatId in _selected) {
      try {
        if (widget._isForward) {
          final ok = await _api.forwardMessage(
              widget.forwardMessageId!, chatId);
          if (ok) successCount++;
        } else if (widget._isShare) {
          // 1) Сначала текст (если есть)
          if (widget.sharedText != null && widget.sharedText!.isNotEmpty) {
            await _api.sendMessage(chatId, widget.sharedText!);
          }
          // 2) Потом файлы
          if (widget.sharedFiles != null) {
            for (final file in widget.sharedFiles!) {
              final mime = _guessMime(file.path);
              final fileType = _mimeToFileType(mime);
              final result = await _api.uploadFile(file, mime);
              if (result != null) {
                await _api.sendMessage(chatId, '',
                    fileUrl: result['url'] as String?,
                    fileType: fileType);
              }
            }
          }
          successCount++;
        }
      } catch (_) {
        // продолжаем для остальных чатов
      }
      if (mounted) setState(() => _progress++);
    }

    if (!mounted) return;
    setState(() => _sending = false);

    final msg = widget._isForward
        ? 'Переслано в $successCount из ${_selected.length}'
        : 'Отправлено в $successCount из ${_selected.length}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
    Navigator.pop(context, successCount);
  }

  String _mimeToFileType(String mime) {
    if (mime.startsWith('image/')) return 'IMAGE';
    if (mime.startsWith('video/')) return 'VIDEO';
    if (mime.startsWith('audio/')) return 'AUDIO';
    return 'FILE';
  }

  /// Простой mapping расширения → mime для базовых типов. Достаточно
  /// для шаринга — сервер всё равно сохранит фактическое содержимое.
  String _guessMime(String path) {
    final ext = path.toLowerCase().split('.').last;
    const map = <String, String>{
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
      'gif': 'image/gif', 'webp': 'image/webp', 'heic': 'image/heic',
      'mp4': 'video/mp4', 'mov': 'video/quicktime', 'mkv': 'video/x-matroska',
      'webm': 'video/webm',
      'mp3': 'audio/mpeg', 'wav': 'audio/wav', 'ogg': 'audio/ogg',
      'm4a': 'audio/mp4', 'opus': 'audio/opus',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'zip': 'application/zip', 'rar': 'application/vnd.rar',
      '7z': 'application/x-7z-compressed',
      'txt': 'text/plain', 'csv': 'text/csv', 'json': 'application/json',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  // ─── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(widget._isForward
            ? 'Переслать в...'
            : 'Поделиться в...'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _sending ? _buildSendingProgress() : _buildPicker(),
      bottomNavigationBar: _sending ? null : _buildBottomBar(),
    );
  }

  Widget _buildSendingProgress() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            widget._isForward
                ? 'Пересылаем... $_progress из $_total'
                : 'Отправляем... $_progress из $_total',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildPicker() {
    return Column(
      children: [
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Поиск чатов',
              hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4)),
              prefixIcon: Icon(Icons.search,
                  color: Colors.white.withValues(alpha: 0.4)),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear,
                          color: Colors.white.withValues(alpha: 0.4)),
                      onPressed: () => _searchCtrl.clear())
                  : null,
              filled: true,
              fillColor: AppColors.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),
        // Preview of what's being shared
        if (widget._isShare) _buildSharePreview(),
        // Chats list
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : _filtered.isEmpty
                  ? _buildEmpty()
                  : ListView.separated(
                      itemCount: _filtered.length,
                      separatorBuilder: (_, i) => const SizedBox(height: 0),
                      itemBuilder: (_, i) => _buildChatTile(_filtered[i]),
                    ),
        ),
      ],
    );
  }

  Widget _buildSharePreview() {
    final lines = <String>[];
    if (widget.sharedText?.isNotEmpty == true) {
      lines.add(widget.sharedText!);
    }
    if (widget.sharedFiles?.isNotEmpty == true) {
      lines.add('${widget.sharedFiles!.length} файл(ов)');
    }
    if (lines.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.share, color: AppColors.primary, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Будет отправлено',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(lines.join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.search_off,
            size: 48, color: Colors.white.withValues(alpha: 0.2)),
        const SizedBox(height: 12),
        Text('Ничего не найдено',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
      ]),
    );
  }

  Widget _buildChatTile(Map<String, dynamic> chat) {
    final id = chat['id'] as String;
    final title = chat['title'] as String? ?? '';
    final subtitle = chat['subtitle'] as String? ?? '';
    final image = chat['image'] as String?;
    final type = chat['type'] as String? ?? 'PRIVATE';
    final canWrite = chat['canWrite'] == true;
    final isSelected = _selected.contains(id);

    return InkWell(
      onTap: () => _toggle(id, canWrite),
      child: Opacity(
        opacity: canWrite ? 1.0 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          child: Row(children: [
            // Avatar
            Stack(children: [
              ColoredAvatar(imageUrl: image, title: title, size: 44),
              if (isSelected)
                Positioned(
                  right: -2, bottom: -2,
                  child: Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary,
                      border: Border.all(
                          color: AppColors.background, width: 2),
                    ),
                    child: const Icon(Icons.check,
                        color: Colors.white, size: 12),
                  ),
                ),
            ]),
            const SizedBox(width: 14),
            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    if (type == 'CHANNEL')
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.tag,
                            size: 14, color: AppColors.primary),
                      ),
                    Expanded(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                Colors.white.withValues(alpha: 0.5))),
                  ],
                  if (!canWrite) ...[
                    const SizedBox(height: 2),
                    Text(
                      type == 'CHANNEL'
                          ? 'Только администраторы могут писать'
                          : 'Нет прав на отправку',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFF87171),
                          fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final count = _selected.length;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        child: Row(children: [
          Text(
            count == 0
                ? 'Не выбрано'
                : 'Выбрано: $count ${_pluralChats(count)}',
            style: const TextStyle(color: Colors.white70),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: count == 0 ? null : _confirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor:
                  AppColors.primary.withValues(alpha: 0.3),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 22, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(widget._isForward
                  ? Icons.send_outlined
                  : Icons.share_outlined),
              const SizedBox(width: 8),
              Text(widget._isForward ? 'Переслать' : 'Отправить'),
            ]),
          ),
        ]),
      ),
    );
  }

  String _pluralChats(int n) {
    final last = n % 10;
    final tens = n % 100;
    if (tens >= 11 && tens <= 14) return 'чатов';
    if (last == 1) return 'чат';
    if (last >= 2 && last <= 4) return 'чата';
    return 'чатов';
  }
}
