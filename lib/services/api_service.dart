import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../models/chat.dart';
import '../models/message.dart';

class ApiService {
  static const String baseUrl = 'http://194.87.201.226/api/mobile';

  String? _token;

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    return _token;
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    _token = token;
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    _token = null;
  }

  Future<Map<String, String>> _headers() async {
    await getToken();
    return {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };
  }

  Map<String, dynamic>? _decode(http.Response res) {
    try {
      final body = res.body.trim();
      if (body.isEmpty || body.startsWith('<')) return null;
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ─── Auth ────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      final data = _decode(res);
      if (data != null && data['success'] == true) {
        await _saveToken(data['token']);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', data['user']['id'] ?? '');
        await prefs.setString('user_display_name',
            data['user']['displayName'] ?? data['user']['username'] ?? '');
        return {'success': true, 'user': User.fromJson(data['user'])};
      }
      return {'success': false, 'error': data?['error'] ?? 'Ошибка входа'};
    } catch (e) {
      return {'success': false, 'error': 'Нет соединения с сервером'};
    }
  }

  Future<Map<String, dynamic>> register(
      String email, String password, String username, String displayName) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email, 'password': password,
          'username': username, 'displayName': displayName,
        }),
      );
      final data = _decode(res);
      if (data != null && data['success'] == true) {
        return await login(email, password);
      }
      return {'success': false, 'error': data?['error'] ?? 'Ошибка регистрации'};
    } catch (_) {
      return {'success': false, 'error': 'Нет соединения с сервером'};
    }
  }

  // ─── Sidebar ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getSidebar() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/chats/sidebar'),
        headers: await _headers(),
      );
      final data = _decode(res);
      if (data != null && data['success'] == true) {
        final chats = (data['data']['chats'] as List)
            .map((c) => Chat.fromSidebar(c))
            .toList();
        return {
          'success': true,
          'chats': chats,
          'servers': data['data']['servers'] ?? [],
        };
      }
    } catch (e) {
      print('[SIDEBAR] exception: $e');
    }
    return {'success': false, 'chats': <Chat>[], 'servers': []};
  }

  // ─── Messages ────────────────────────────────────────────────────────────────

  Future<List<Message>> getMessages(String chatId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/messages/$chatId'),
        headers: await _headers(),
      );
      final data = _decode(res);
      if (data != null && data['success'] == true) {
        return (data['data'] as List).map((m) => Message.fromJson(m)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<Message>> getMessagesPaginated(String chatId,
      {int page = 1, int limit = 30}) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/messages/$chatId?page=$page&limit=$limit'),
        headers: await _headers(),
      );
      final data = _decode(res);
      if (data != null && data['success'] == true) {
        return (data['data'] as List).map((m) => Message.fromJson(m)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<Message?> sendMessage(String chatId, String content,
      {String? fileUrl, String? fileType, String? replyToId}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/messages/send'),
        headers: await _headers(),
        body: jsonEncode({
          'chatId': chatId,
          'content': content,
          if (fileUrl != null) 'fileUrl': fileUrl,
          if (fileType != null) 'fileType': fileType,
          if (replyToId != null) 'replyToId': replyToId,
        }),
      );
      final data = _decode(res);
      if (data != null && data['success'] == true) {
        return Message.fromJson(data['data']);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> editMessage(String messageId, String content) async {
    try {
      final res = await http.patch(
        Uri.parse('$baseUrl/messages/edit'),
        headers: await _headers(),
        body: jsonEncode({'messageId': messageId, 'content': content}),
      );
      return _decode(res)?['success'] == true;
    } catch (_) { return false; }
  }

  Future<bool> deleteMessage(String messageId) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/messages/delete'),
        headers: await _headers(),
        body: jsonEncode({'messageId': messageId}),
      );
      return _decode(res)?['success'] == true;
    } catch (_) { return false; }
  }

  Future<void> markAsRead(String chatId) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/messages/read'),
        headers: await _headers(),
        body: jsonEncode({'chatId': chatId}),
      );
    } catch (_) {}
  }

  Future<bool> addReaction(String messageId, String reaction) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/messages/reactions'),
        headers: await _headers(),
        body: jsonEncode({'messageId': messageId, 'reaction': reaction}),
      );
      return _decode(res)?['success'] == true;
    } catch (_) { return false; }
  }

  Future<bool> removeReaction(String messageId, String reaction) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/messages/reactions'),
        headers: await _headers(),
        body: jsonEncode({'messageId': messageId, 'reaction': reaction}),
      );
      return _decode(res)?['success'] == true;
    } catch (_) { return false; }
  }

  /// Перенаправить сообщение в один чат. API принимает один targetChatId
  /// за вызов — для нескольких чатов нужен цикл вызовов на стороне UI.
  Future<bool> forwardMessage(String messageId, String targetChatId) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/messages/forward'),
        headers: await _headers(),
        body: jsonEncode({'messageId': messageId, 'targetChatId': targetChatId}),
      );
      return _decode(res)?['success'] == true;
    } catch (_) { return false; }
  }

  /// Все чаты пользователя с флагом `canWrite` — для пересылки и шеринга
  /// контента из других приложений.
  Future<List<Map<String, dynamic>>> getAvailableChats() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/chats/available'),
        headers: await _headers(),
      );
      final data = _decode(res);
      if (data?['success'] == true && data?['data'] is List) {
        return (data!['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  Future<void> saveFcmToken(String token) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/fcm/token'),
        headers: await _headers(),
        body: jsonEncode({'token': token}),
      );
    } catch (_) {}
  }

  Future<void> deleteFcmToken() async {
    try {
      await http.delete(
        Uri.parse('$baseUrl/fcm/token'),
        headers: await _headers(),
      );
    } catch (_) {}
  }
  Future<void> sendTyping(String chatId, bool isTyping) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/messages/typing'),
        headers: await _headers(),
        body: jsonEncode({'chatId': chatId, 'isTyping': isTyping}),
      );
    } catch (_) {}
  }

  // ─── Profile ─────────────────────────────────────────────────────────────────

  Future<User?> getProfile() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/profile'),
        headers: await _headers(),
      );
      final data = _decode(res);
      if (data != null && data['success'] == true) return User.fromJson(data['profile']);
    } catch (_) {}
    return null;
  }

  Future<User?> updateProfile(
      {String? displayName, String? bio, String? status, String? avatarUrl,
       Map<String, dynamic>? socialLinks}) async {
    try {
      final res = await http.patch(
        Uri.parse('$baseUrl/profile'),
        headers: await _headers(),
        body: jsonEncode({
          if (displayName != null) 'displayName': displayName,
          if (bio != null) 'bio': bio,
          if (status != null) 'status': status,
          if (avatarUrl != null) 'avatarUrl': avatarUrl,
          if (socialLinks != null) 'socialLinks': socialLinks,
        }),
      );
      final data = _decode(res);
      if (data != null && data['success'] == true) return User.fromJson(data['profile']);
    } catch (_) {}
    return null;
  }

  // ─── Settings ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getSettings() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/settings'),
        headers: await _headers(),
      );
      final data = _decode(res);
      if (data != null && data['success'] == true) return data['settings'];
    } catch (_) {}
    return null;
  }

  Future<bool> updateSettings(Map<String, dynamic> settings) async {
    try {
      final res = await http.patch(
        Uri.parse('$baseUrl/settings'),
        headers: await _headers(),
        body: jsonEncode(settings),
      );
      return _decode(res)?['success'] == true;
    } catch (_) { return false; }
  }

  // ─── Search ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> search(String query) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/search?q=${Uri.encodeComponent(query)}'),
        headers: await _headers(),
      );
      final data = _decode(res);
      if (data != null && data['success'] == true) {
        return {
          'users': List<Map<String, dynamic>>.from(data['data']['users'] ?? []),
          'chats': List<Map<String, dynamic>>.from(data['data']['chats'] ?? []),
          'servers': List<Map<String, dynamic>>.from(data['data']['servers'] ?? []),
        };
      }
    } catch (_) {}
    return {'users': [], 'chats': [], 'servers': []};
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final result = await search(query);
    return result['users'] as List<Map<String, dynamic>>;
  }

  Future<Map<String, dynamic>?> getUserStatus(String userId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/users/status?userId=$userId'),
        headers: await _headers(),
      );
      final data = _decode(res);
      if (data != null && data['success'] == true) return data['data'] as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  // ─── Create ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> createPrivateChat(String partnerId) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/chats/private'),
        headers: await _headers(),
        body: jsonEncode({'partnerId': partnerId}),
      );
      final data = _decode(res);
      if (data != null && data['success'] == true) return data['chat'] as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> createGroup({
    required String name, required List<String> userIds, String access = 'PUBLIC',
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/chats/create'),
        headers: await _headers(),
        body: jsonEncode({'name': name, 'userIds': userIds, 'access': access}),
      );
      final data = _decode(res);
      if (data != null && data['success'] == true) return data['chat'] as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> createChannel({
    required String name, required List<String> userIds, String access = 'PUBLIC',
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/chats/create'),
        headers: await _headers(),
        body: jsonEncode({'name': name, 'userIds': userIds, 'access': access, 'type': 'CHANNEL'}),
      );
      final data = _decode(res);
      if (data != null && data['success'] == true) return data['chat'] as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> createServer({
    required String name, required List<String> userIds,
    required List<Map<String, String>> channels, String access = 'PUBLIC',
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/chats/server'),
        headers: await _headers(),
        body: jsonEncode({'name': name, 'userIds': userIds, 'channels': channels, 'access': access}),
      );
      final data = _decode(res);
      if (data != null && data['success'] == true) return data['data'] as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  // ─── Calls ───────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> startCall(String chatId, String type) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/calls/webrtc/start'),
        headers: await _headers(),
        body: jsonEncode({'chatId': chatId, 'type': type}),
      );
      final data = _decode(res);
      if (data != null && data['success'] == true) return data;
    } catch (_) {}
    return null;
  }

  Future<String?> fetchOffer(String callId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/calls/webrtc/offer?callId=$callId'),
        headers: await _headers(),
      );
      final data = _decode(res);
      if (data != null && data['success'] == true && data['hasOffer'] == true) {
        return data['sdp'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// Получает актуальную ICE-конфигурацию (STUN/TURN) с сервера.
  /// Сервер читает её из переменных окружения, поэтому креды TURN не лежат в
  /// клиентском коде. См. app/api/mobile/calls/ice-config/route.ts.
  Future<Map<String, dynamic>?> fetchIceConfig() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/calls/ice-config'),
        headers: await _headers(),
      );
      final data = _decode(res);
      if (data != null && data['success'] == true && data['iceServers'] is List) {
        return {
          'iceServers': data['iceServers'],
          'iceCandidatePoolSize': data['iceCandidatePoolSize'] ?? 2,
          'bundlePolicy': data['bundlePolicy'] ?? 'max-bundle',
          'rtcpMuxPolicy': data['rtcpMuxPolicy'] ?? 'require',
          'sdpSemantics': 'unified-plan',
        };
      }
    } catch (_) {}
    return null;
  }

  // ─── Upload ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> uploadFile(File file, String mimeType) async {
    try {
      await getToken();
      final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
      if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
      final parts = mimeType.split('/');
      req.files.add(await http.MultipartFile.fromPath(
        'file', file.path,
        contentType: MediaType(parts[0], parts.length > 1 ? parts[1] : '*'),
      ));
      final streamed = await req.send();
      final body = await streamed.stream.bytesToString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['success'] == true) return {'url': json['url'], 'fileName': json['fileName']};
    } catch (_) {}
    return null;
  }

  // ─── User Profile ────────────────────────────────────────────────────────────

  /// Полный профиль другого пользователя.
  /// Возвращает уже распакованный `data` объект (см. web shape getUserProfile).
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/users/$userId'),
        headers: await _headers(),
      );
      final data = _decode(res);
      if (data?['success'] == true && data?['data'] is Map) {
        return Map<String, dynamic>.from(data!['data'] as Map);
      }
    } catch (_) {}
    return null;
  }

  /// Медиа-файлы из приватного чата с пользователем.
  /// Возвращает `{ photos: [], videos: [], files: [], audio: [] }`.
  Future<Map<String, dynamic>?> getUserMediaFiles(String userId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/users/media?userId=$userId'),
        headers: await _headers(),
      );
      final data = _decode(res);
      if (data?['success'] == true && data?['data'] is Map) {
        return Map<String, dynamic>.from(data!['data'] as Map);
      }
    } catch (_) {}
    return null;
  }

  /// Существующий приватный чат с пользователем или создание нового.
  /// Возвращает чат-объект `{ id, name, type, imageUrl, ... }`.
  Future<Map<String, dynamic>?> getOrCreatePrivateChat(String partnerId) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/chats/private'),
        headers: await _headers(),
        body: jsonEncode({'partnerId': partnerId}),
      );
      final data = _decode(res);
      if (data?['success'] == true && data?['chat'] is Map) {
        return Map<String, dynamic>.from(data!['chat'] as Map);
      }
    } catch (_) {}
    return null;
  }

  /// Статус блокировки между текущим пользователем и `targetId`.
  /// `{ iBlockedThem: bool, theyBlockedMe: bool }`.
  Future<Map<String, bool>> getBlockStatus(String targetId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/users/block?targetId=$targetId'),
        headers: await _headers(),
      );
      final data = _decode(res);
      if (data?['success'] == true && data?['data'] is Map) {
        final d = data!['data'] as Map;
        return {
          'iBlockedThem': d['iBlockedThem'] == true,
          'theyBlockedMe': d['theyBlockedMe'] == true,
        };
      }
    } catch (_) {}
    return {'iBlockedThem': false, 'theyBlockedMe': false};
  }

  Future<bool> blockUser(String targetId) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/users/block'),
        headers: await _headers(),
        body: jsonEncode({'targetId': targetId}),
      );
      final data = _decode(res);
      return data?['success'] == true;
    } catch (_) {}
    return false;
  }

  Future<bool> unblockUser(String targetId) async {
    try {
      final req = http.Request('DELETE', Uri.parse('$baseUrl/users/block'))
        ..headers.addAll(await _headers())
        ..body = jsonEncode({'targetId': targetId});
      final streamed = await req.send();
      final body = await streamed.stream.bytesToString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      return data['success'] == true;
    } catch (_) {}
    return false;
  }

  // ─── Chat Details ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getChatDetails(String chatId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/chats/$chatId'),
        headers: await _headers(),
      );
      final data = _decode(res);
      if (data?['success'] == true) return data?['data'] as Map<String, dynamic>?;
    } catch (_) {}
    return null;
  }

  Future<bool> leaveChat(String chatId) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/chats/members'),
        headers: await _headers(),
        body: jsonEncode({'chatId': chatId}),
      );
      final data = _decode(res);
      return data?['success'] == true;
    } catch (_) {}
    return false;
  }

  // ─── Chat/Server management ─────────────────────────────────────────────────

  Future<bool> updateChat(String chatId, {String? name, String? imageUrl, String? access}) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (imageUrl != null) body['imageUrl'] = imageUrl;
      if (access != null) body['access'] = access;
      final res = await http.patch(
        Uri.parse('$baseUrl/chats/$chatId'),
        headers: await _headers(),
        body: jsonEncode(body),
      );
      final data = _decode(res);
      return data?['success'] == true;
    } catch (_) {}
    return false;
  }

  Future<bool> deleteChat(String chatId) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/chats/$chatId'),
        headers: await _headers(),
      );
      final data = _decode(res);
      return data?['success'] == true;
    } catch (_) {}
    return false;
  }

  Future<bool> createServerChannel(String serverId, {required String name, required String type}) async {
    try {
      final res = await http.patch(
        Uri.parse('$baseUrl/chats/server'),
        headers: await _headers(),
        body: jsonEncode({'serverId': serverId, 'name': name, 'type': type}),
      );
      final data = _decode(res);
      return data?['success'] == true;
    } catch (_) {}
    return false;
  }
}
