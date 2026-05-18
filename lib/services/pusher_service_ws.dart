import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class PusherService {
  static const _key = 'c49c78eb08da2488b4a0';
  static const _wsUrl =
      'wss://ws-eu.pusher.com/app/$_key?protocol=7&client=flutter&version=1.0&flash=false';

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  String? _socketId;

  // channel -> event -> callbacks
  final Map<String, Map<String, List<void Function(Map<String, dynamic>)>>> _listeners = {};

  Future<void> _ensureConnected() async {
    if (_channel != null) return;
    _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
    _sub = _channel!.stream.listen(
      _onMessage,
      onDone: () => _channel = null,
      onError: (_) => _channel = null,
    );
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final event = msg['event'] as String?;
      final channel = msg['channel'] as String?;
      final dataRaw = msg['data'];

      if (event == 'pusher:connection_established') {
        final data = jsonDecode(dataRaw as String) as Map<String, dynamic>;
        _socketId = data['socket_id'] as String?;
        return;
      }

      if (channel == null || event == null) return;

      final data = dataRaw is String
          ? (jsonDecode(dataRaw) as Map<String, dynamic>)
          : (dataRaw as Map<String, dynamic>);

      final cbs = _listeners[channel]?[event];
      if (cbs != null) {
        for (final cb in cbs) {
          cb(data);
        }
      }
    } catch (_) {}
  }

  void _subscribe(String channelName) {
    _channel?.sink.add(jsonEncode({
      'event': 'pusher:subscribe',
      'data': {'channel': channelName},
    }));
  }

  void subscribeToUserChannel(
    String userId, {
    required void Function(Map<String, dynamic>) onIncomingCall,
    required void Function(Map<String, dynamic>) onOutgoingCall,
  }) {
    final channel = 'user-$userId';
    _ensureConnected().then((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _subscribe(channel);
        _addListener(channel, 'incoming-call', onIncomingCall);
        _addListener(channel, 'outgoing-call', onOutgoingCall);
      });
    });
  }

  void unsubscribeFromUserChannel(String userId) {
    final channel = 'user-$userId';
    _channel?.sink.add(jsonEncode({
      'event': 'pusher:unsubscribe',
      'data': {'channel': channel},
    }));
    _listeners.remove(channel);
  }

  void subscribeToChat(
    String chatId, {
    required void Function(Map<String, dynamic>) onNewMessage,
    void Function(Map<String, dynamic>)? onMessageUpdated,
    void Function(String)? onMessageDeleted,
  }) {
    _ensureConnected().then((_) {
      // Небольшая задержка чтобы дождаться connection_established
      Future.delayed(const Duration(milliseconds: 500), () {
        _subscribe(chatId);
        _addListener(chatId, 'new-message', onNewMessage);
        if (onMessageUpdated != null) {
          _addListener(chatId, 'message-updated', onMessageUpdated);
        }
        if (onMessageDeleted != null) {
          _addListener(chatId, 'message-deleted', (data) {
            onMessageDeleted(data['id']?.toString() ?? jsonEncode(data));
          });
        }
      });
    });
  }

  void _addListener(String channel, String event, void Function(Map<String, dynamic>) cb) {
    _listeners.putIfAbsent(channel, () => {}).putIfAbsent(event, () => []).add(cb);
  }

  void unsubscribe(String chatId) {
    _channel?.sink.add(jsonEncode({
      'event': 'pusher:unsubscribe',
      'data': {'channel': chatId},
    }));
    _listeners.remove(chatId);
  }

  void disconnect() {
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _listeners.clear();
  }
}
