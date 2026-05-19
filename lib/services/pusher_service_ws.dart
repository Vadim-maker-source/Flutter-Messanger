import 'dart:convert';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

class PusherService {
  static final PusherService _instance = PusherService._internal();
  factory PusherService() => _instance;
  PusherService._internal();

  static const _key = 'c49c78eb08da2488b4a0';
  static const _cluster = 'eu';

  final _pusher = PusherChannelsFlutter.getInstance();
  bool _initialized = false;

  Future<void> _ensureConnected() async {
    if (_initialized) return;
    print('[PUSHER] initializing...');
    await _pusher.init(
      apiKey: _key,
      cluster: _cluster,
      onConnectionStateChange: (current, previous) =>
          print('[PUSHER] state: $previous -> $current'),
      onError: (message, code, error) =>
          print('[PUSHER] error: $message code=$code error=$error'),
    );
    await _pusher.connect();
    _initialized = true;
    print('[PUSHER] connected');
  }

  Map<String, dynamic> _parse(dynamic data) {
    if (data is String) return jsonDecode(data) as Map<String, dynamic>;
    return data as Map<String, dynamic>;
  }

  Future<void> _sub(String channel, void Function(PusherEvent) onEvent) async {
    await _ensureConnected();
    try {
      await _pusher.subscribe(
        channelName: channel,
        onEvent: (dynamic event) => onEvent(event as PusherEvent),
      );
    } catch (e) {
      print('[PUSHER] subscribe error ($channel): $e');
    }
  }

  void subscribeToChat(
    String chatId, {
    required void Function(Map<String, dynamic>) onNewMessage,
    void Function(Map<String, dynamic>)? onMessageUpdated,
    void Function(String)? onMessageDeleted,
    void Function(List<String>)? onMessagesRead,
  }) {
    _sub(chatId, (event) {
      print('[PUSHER] event on $chatId: ${event.eventName} data=${event.data}');
      final data = _parse(event.data);
      switch (event.eventName) {
        case 'new-message':
          onNewMessage(data);
        case 'message-updated':
          onMessageUpdated?.call(data);
        case 'message-deleted':
          onMessageDeleted?.call(data['id']?.toString() ?? '');
        case 'messages-read':
          final ids = (data['messageIds'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          onMessagesRead?.call(ids);
      }
    });
  }

  void subscribeToPresence(
      void Function(String userId, bool isOnline, String? lastActive) onChange) {
    _sub('presence', (event) {
      if (event.eventName != 'user-status-change') return;
      final data = _parse(event.data);
      onChange(
        data['userId'] as String,
        data['isOnline'] as bool? ?? false,
        data['lastActive'] as String?,
      );
    });
  }

  void subscribeToUserChannel(
    String userId, {
    required void Function(Map<String, dynamic>) onIncomingCall,
    required void Function(Map<String, dynamic>) onOutgoingCall,
  }) {
    print('[PUSHER] subscribing to user-$userId');
    _sub('user-$userId', (event) {
      print('[PUSHER] user channel event: ${event.eventName}');
      final data = _parse(event.data);
      switch (event.eventName) {
        case 'incoming-call':
          onIncomingCall(data);
        case 'outgoing-call':
          onOutgoingCall(data);
      }
    });
  }

  void unsubscribe(String channel) => _pusher.unsubscribe(channelName: channel);
  void unsubscribeFromUserChannel(String userId) => unsubscribe('user-$userId');
  void unsubscribeFromPresence() => unsubscribe('presence');

  void disconnect() {
    _pusher.disconnect();
    _initialized = false;
  }
}
