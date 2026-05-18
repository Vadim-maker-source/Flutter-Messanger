import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/chat.dart';
import 'chat_screen.dart';

class NewPrivateChatScreen extends StatefulWidget {
  const NewPrivateChatScreen({super.key});

  @override
  State<NewPrivateChatScreen> createState() => _NewPrivateChatScreenState();
}

class _NewPrivateChatScreenState extends State<NewPrivateChatScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    final res = await _api.searchUsers(q);
    setState(() {
      _results = res;
      _searching = false;
    });
  }

  Future<void> _openChat(Map<String, dynamic> user) async {
    final chat = await _api.createPrivateChat(user['id'] as String);
    if (chat != null && mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => ChatScreen(chat: Chat.fromJson({
          'id': chat['id'],
          'title': user['displayName'] ?? user['username'],
          'imageUrl': user['avatarUrl'],
          'type': 'PRIVATE',
        })),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новый чат')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: 'Поиск по username или имени...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ) : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _searchCtrl.text.isEmpty ? 'Введите имя или username' : 'Никого не найдено',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final u = _results[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: u['avatarUrl'] != null ? NetworkImage(u['avatarUrl']) : null,
                          child: u['avatarUrl'] == null
                              ? Text((u['username'] as String? ?? '?')[0].toUpperCase())
                              : null,
                        ),
                        title: Text(u['displayName'] ?? u['username'] ?? ''),
                        subtitle: Text('@${u['username']}'),
                        onTap: () => _openChat(u),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
