import 'dart:async';
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'api_service.dart';

/// Сервис связи в реальном времени через Socket.io.
///
/// Файл назван pusher_service_ws.dart по историческим причинам — раньше тут
/// был pusher_channels_flutter. API класса (subscribeToUserChannel и т.д.)
/// сохранён, чтобы код, который его использует, не пришлось трогать.
///
/// Внутри теперь Socket.io. Подключение к `${ApiService.baseUrl}` (без
/// /api/mobile хвоста), путь `/socket.io`. Авторизация — по тому же JWT,
/// что и в HTTP-запросах.
class PusherService {
  static final PusherService _instance = PusherService._internal();
  factory PusherService() => _instance;
  PusherService._internal();

  IO.Socket? _socket;
  bool _initialized = false;

  // Карта обработчиков на каждый канал (то что раньше было pusher.subscribe)
  final Map<String, void Function(String event, Map<String, dynamic> data)>
      _handlers = {};

  // Получаем origin сервера: ApiService.baseUrl = 'http://192.168.0.109:3000/api/mobile'
  // → нужен 'http://192.168.0.109:3000'
  String get _serverOrigin {
    final url = Uri.parse(ApiService.baseUrl);
    return '${url.scheme}://${url.authority}';
  }

  Future<void> _ensureConnected() async {
    if (_initialized && _socket?.connected == true) return;
    if (_initialized) return; // уже подключаемся

    _initialized = true;

    // Берём JWT-токен — тот же что для HTTP-запросов.
    final api = ApiService();
    final token = await api.getToken();
    if (token == null || token.isEmpty) {
      print('[PUSHER] init failed: no auth token');
      _initialized = false;
      return;
    }

    print('[PUSHER] init server=$_serverOrigin');
    _socket = IO.io(
      _serverOrigin,
      IO.OptionBuilder()
          .setPath('/socket.io')
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          .setReconnectionAttempts(0xFFFFFFF) // ~бесконечно
          .build(),
    );

    _socket!.onConnect((_) => print('[PUSHER] state -> CONNECTED (id=${_socket!.id})'));
    _socket!.onDisconnect((reason) => print('[PUSHER] state -> DISCONNECTED ($reason)'));
    _socket!.onConnectError((err) => print('[PUSHER] connect error: $err'));
    _socket!.onError((err) => print('[PUSHER] error: $err'));

    // На каждый reconnect — переподписаться на каналы
    _socket!.onReconnect((_) {
      print('[PUSHER] reconnected, re-subscribing to ${_handlers.keys.length} channels');
      for (final ch in _handlers.keys) {
        _socket!.emit('subscribe', ch);
      }
    });

    _socket!.connect();
  }

  Map<String, dynamic> _parse(dynamic data) {
    if (data is String) {
      try {
        return jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        return {};
      }
    }
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  /// Подписка на канал. Сервер будет слать события под именем
  /// `${channel}:${event}` — внутри маппинга вызываем onEvent с распарсенными
  /// данными.
  Future<void> _sub(
    String channel,
    void Function(String event, Map<String, dynamic> data) onEvent,
  ) async {
    await _ensureConnected();
    if (_socket == null) return;

    _handlers[channel] = onEvent;

    // emit subscribe — server проверяет права и добавляет socket в room
    _socket!.emitWithAck('subscribe', channel, ack: (resp) {
      if (resp is Map && resp['success'] == true) {
        print('[PUSHER] subscribed to $channel');
      } else {
        print('[PUSHER] subscribe rejected: $channel ($resp)');
      }
    });

    // Регистрируем динамический слушатель: socket.io ловит ЛЮБЫЕ event-имена
    // через onAny, и мы фильтруем по префиксу `${channel}:`.
    // Делаем это глобально один раз, а не для каждого канала.
    if (!_anyListenerInstalled) {
      _anyListenerInstalled = true;
      _socket!.onAny((eventName, data) {
        final idx = eventName.indexOf(':');
        if (idx <= 0) return;
        final ch = eventName.substring(0, idx);
        final ev = eventName.substring(idx + 1);
        final handler = _handlers[ch];
        if (handler != null) {
          handler(ev, _parse(data));
        }
      });
    }
  }

  bool _anyListenerInstalled = false;

  // ─── Chat channel ──────────────────────────────────────────────────────────

  void subscribeToChat(
    String chatId, {
    required void Function(Map<String, dynamic>) onNewMessage,
    void Function(Map<String, dynamic>)? onMessageUpdated,
    void Function(String)? onMessageDeleted,
    void Function(List<String>)? onMessagesRead,
    void Function(String userId, String displayName)? onTypingStart,
    void Function(String userId)? onTypingStop,
    void Function(String messageId, Map<String, dynamic> reactions)? onReactionUpdated,
  }) {
    _sub(chatId, (event, data) {
      switch (event) {
        case 'new-message':
          onNewMessage(data);
        case 'message-updated':
          onMessageUpdated?.call(data);
        case 'message-deleted':
          // Сервер шлёт messageId как строку (не объект)
          // socket.io передаёт это как саму строку, а _parse вернёт {}
          // → специальный кейс: pусht.io обрабатывал это как payload.id
          // Здесь мы получаем уже распарсенную data — но в случае строкового
          // payload она будет пустой. Чтобы не сломать поведение, проверяем
          // обе возможности.
          final id = data['id']?.toString() ??
              data['messageId']?.toString() ??
              '';
          onMessageDeleted?.call(id);
        case 'messages-read':
          final ids = (data['messageIds'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          onMessagesRead?.call(ids);
        case 'typing-start':
          onTypingStart?.call(
            data['userId']?.toString() ?? '',
            data['displayName']?.toString() ?? '',
          );
        case 'typing-stop':
          onTypingStop?.call(data['userId']?.toString() ?? '');
        case 'reaction-updated':
          onReactionUpdated?.call(
            data['messageId']?.toString() ?? '',
            Map<String, dynamic>.from(data['reactions'] ?? {}),
          );
      }
    });
  }

  // ─── Presence (online status) ──────────────────────────────────────────────

  void subscribeToPresence(
      void Function(String userId, bool isOnline, String? lastActive) onChange) {
    _sub('presence', (event, data) {
      if (event != 'user-status-change') return;
      onChange(
        data['userId'] as String? ?? '',
        data['isOnline'] as bool? ?? false,
        data['lastActive'] as String?,
      );
    });
  }

  // ─── Sidebar channel (unread updates) ──────────────────────────────────────

  void subscribeToSidebar(
    String userId, {
    required void Function(String chatId, int unreadCount, Map<String, dynamic>? lastMessage) onUpdate,
  }) {
    _sub('sidebar-$userId', (event, data) {
      if (event != 'sidebar-update') return;
      onUpdate(
        data['chatId']?.toString() ?? '',
        (data['unreadCount'] as num?)?.toInt() ?? 0,
        data['lastMessage'] as Map<String, dynamic>?,
      );
    });
  }

  // ─── User channel (calls) ──────────────────────────────────────────────────

  /// Глобальный поток событий блокировки. Любой экран может подписаться,
  /// чтобы реагировать на изменения статуса в реальном времени.
  ///
  /// Полезная нагрузка:
  ///   • `targetId` — ID пользователя, статус с которым изменился
  ///   • `iBlockedThem` или `theyBlockedMe` — что произошло
  final _blockUpdates = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get blockUpdates => _blockUpdates.stream;

  void subscribeToUserChannel(
    String userId, {
    required void Function(Map<String, dynamic>) onIncomingCall,
    required void Function(Map<String, dynamic>) onOutgoingCall,
    void Function(Map<String, dynamic>)? onWebRtcSignal,
    void Function(Map<String, dynamic>)? onCallAcceptedElsewhere,
  }) {
    print('[PUSHER] subscribeToUserChannel userId=$userId');
    _sub('user-$userId', (event, data) {
      switch (event) {
        case 'incoming-call':
          print('[PUSHER] -> incoming-call');
          onIncomingCall(data);
        case 'outgoing-call':
          print('[PUSHER] -> outgoing-call');
          onOutgoingCall(data);
        case 'webrtc-signal':
          print('[PUSHER] -> webrtc-signal type=${data['type']}');
          onWebRtcSignal?.call(data);
        case 'call-accepted-elsewhere':
          print('[PUSHER] -> call-accepted-elsewhere');
          onCallAcceptedElsewhere?.call(data);
        case 'block-update':
          print('[PUSHER] -> block-update');
          _blockUpdates.add(data);
      }
    });
  }

  // ─── Unsubscribe ───────────────────────────────────────────────────────────

  void unsubscribe(String channel) {
    _handlers.remove(channel);
    _socket?.emit('unsubscribe', channel);
  }

  void unsubscribeFromUserChannel(String userId) => unsubscribe('user-$userId');
  void unsubscribeFromPresence() => unsubscribe('presence');
  void unsubscribeFromSidebar(String userId) => unsubscribe('sidebar-$userId');

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
    _initialized = false;
    _handlers.clear();
    _anyListenerInstalled = false;
  }
}
