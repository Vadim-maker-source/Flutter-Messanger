import 'package:flutter/material.dart';
import '../main.dart' show AppColors;
import '../services/api_service.dart';

/// Bottom-sheet для добавления участников в чат или сервер.
///
/// Показывает поиск по пользователям, multi-select с чипсами и кнопку
/// "Добавить N". Использует одинаковый стиль с диалогом смены пароля.
///
/// Передавайте либо [chatId], либо [serverId] (но не оба).
Future<int?> showAddMemberSheet(
  BuildContext context, {
  String? chatId,
  String? serverId,
  List<String> existingMemberIds = const [],
}) {
  assert((chatId != null) ^ (serverId != null),
      'Pass either chatId or serverId, not both');
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => _AddMemberSheet(
      chatId: chatId,
      serverId: serverId,
      existing: existingMemberIds.toSet(),
    ),
  );
}

class _AddMemberSheet extends StatefulWidget {
  final String? chatId;
  final String? serverId;
  final Set<String> existing;
  const _AddMemberSheet({
    required this.chatId,
    required this.serverId,
    required this.existing,
  });

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  final Set<String> _selected = {};
  final List<Map<String, dynamic>> _selectedUsers = [];
  bool _searching = false;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    final res = await _api.searchUsers(q);
    if (!mounted) return;
    setState(() {
      _users = res
          .where((u) => !widget.existing.contains(u['id'] as String))
          .toList();
      _searching = false;
    });
  }

  void _toggle(Map<String, dynamic> user) {
    final id = user['id'] as String;
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        _selectedUsers.removeWhere((u) => u['id'] == id);
      } else {
        _selected.add(id);
        _selectedUsers.add(user);
      }
    });
  }

  Future<void> _add() async {
    if (_selected.isEmpty) return;
    setState(() => _adding = true);
    int added = 0;
    for (final id in _selected) {
      final ok = widget.serverId != null
          ? await _api.addServerMember(widget.serverId!, id)
          : await _api.addChatMember(widget.chatId!, id);
      if (ok) added++;
    }
    if (!mounted) return;
    setState(() => _adding = false);
    Navigator.pop(context, added);
    if (added > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Добавлено: $added')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось добавить')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF16161B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(bottom: keyboardHeight),
        child: Column(children: [
          // Drag handle
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.person_add_alt_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Добавить участников',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  Text('Выберите кого пригласить',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.5))),
                ],
              )),
              IconButton(
                icon: Icon(Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.4)),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),

          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1F1F26),
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 14.5),
                onChanged: _search,
                decoration: InputDecoration(
                  hintText: 'Поиск по имени или @username',
                  hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3)),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 20, color: Colors.white.withValues(alpha: 0.4)),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.primary),
                          ),
                        )
                      : null,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),

          // Selected chips
          if (_selectedUsers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Wrap(spacing: 8, runSpacing: 8, children:
                  _selectedUsers.map((u) {
                return GestureDetector(
                  onTap: () => _toggle(u),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _Avatar(user: u, size: 22),
                      const SizedBox(width: 6),
                      Text(u['displayName'] ?? u['username'] ?? '',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      const Icon(Icons.close_rounded,
                          size: 13, color: AppColors.primary),
                    ]),
                  ),
                );
              }).toList()),
            ),

          // List
          Expanded(
            child: _users.isEmpty && !_searching
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.search_rounded,
                          size: 36,
                          color: Colors.white.withValues(alpha: 0.15)),
                      const SizedBox(height: 8),
                      Text('Никого не найдено',
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.4))),
                    ]),
                  )
                : ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _users.length,
                    itemBuilder: (_, i) {
                      final u = _users[i];
                      final selected = _selected.contains(u['id']);
                      return InkWell(
                        onTap: () => _toggle(u),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          margin: const EdgeInsets.symmetric(vertical: 1),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.primary.withValues(alpha: 0.08)
                                : null,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(children: [
                            _Avatar(user: u, size: 40),
                            const SizedBox(width: 12),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(u['displayName'] ?? u['username'] ?? '',
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white),
                                    overflow: TextOverflow.ellipsis),
                                Text('@${u['username']}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white.withValues(alpha: 0.4)),
                                    overflow: TextOverflow.ellipsis),
                              ],
                            )),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 22, height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: selected
                                    ? AppColors.primary
                                    : Colors.transparent,
                                border: Border.all(
                                    color: selected
                                        ? AppColors.primary
                                        : Colors.white.withValues(alpha: 0.2),
                                    width: 1.5),
                              ),
                              child: selected
                                  ? const Icon(Icons.check_rounded,
                                      size: 14, color: Colors.white)
                                  : null,
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
          ),

          // Bottom action
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Material(
                color: _selected.isEmpty
                    ? const Color(0xFF1F1F26)
                    : AppColors.primary,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: _selected.isEmpty || _adding ? null : _add,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    child: _adding
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            _selected.isEmpty
                                ? 'Выберите хотя бы одного'
                                : 'Добавить ${_selected.length}',
                            style: TextStyle(
                                color: _selected.isEmpty
                                    ? Colors.white.withValues(alpha: 0.4)
                                    : Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final Map<String, dynamic> user;
  final double size;
  const _Avatar({required this.user, required this.size});

  @override
  Widget build(BuildContext context) {
    final url = user['avatarUrl'] as String?;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(backgroundImage: NetworkImage(url), radius: size / 2);
    }
    final letter = (user['username'] as String? ?? user['displayName'] as String? ?? '?')
        .characters.first.toUpperCase();
    return Container(
      width: size, height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withValues(alpha: 0.15),
      ),
      child: Text(letter,
          style: TextStyle(
              fontSize: size * 0.42,
              color: AppColors.primary,
              fontWeight: FontWeight.w700)),
    );
  }
}
