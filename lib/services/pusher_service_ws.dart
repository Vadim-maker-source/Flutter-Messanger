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
      onConnectionStateChange: (current, previous) {
        print('[PUSHER] state: $previous -> $current');
      },
      onError: (message, code, error) {
        print('[PUSHER] error: $message code=$code error=$error');
      },
    );
    await _pusher.connect();
    _initialized = true;
    print('[PUSHER] connected');
  }

  Map<String, dynamic> _parse(dynamic data) {
    if (data is String) return jsonDecode(data) as Map<String, dynamic>;
    return data as Map<String, dynamic>;
  }

  void subscribeToChat(
    String chatId, {
    required void Function(Map<String, dynamic>) onNewMessage,
    void Function(Map<String, dynamic>)? onMessageUpdated,
    void Function(String)? onMessageDeleted,
  }) {
    _ensureConnected().then((_) {
      _pusher.subscribe(
        channelName: chatId,
        onEvent: (event) {
          final data = _parse(event.data);
          switch (event.eventName) {
            case 'new-message':
              onNewMessage(data);
            case 'message-updated':
              onMessageUpdated?.call(data);
            case 'message-deleted':
              onMessageDeleted?.call(data['id']?.toString() ?? '');
          }
        },
      );
    });
  }

  void subscribeToUserChannel(
    String userId, {
    required void Function(Map<String, dynamic>) onIncomingCall,
    required void Function(Map<String, dynamic>) onOutgoingCall,
  }) {
    print('[PUSHER] subscribing to user-$userId');
    _ensureConnected().then((_) async {
      try {
        await _pusher.subscribe(
          channelName: 'user-$userId',
          onEvent: (event) {
            print('[PUSHER] user channel event: ${event.eventName} data=${event.data}');
            final data = _parse(event.data);
            switch (event.eventName) {
              case 'incoming-call':
                onIncomingCall(data);
              case 'outgoing-call':
                onOutgoingCall(data);
            }
          },
        );
      } catch (e) {
        print('[PUSHER] subscribe error (likely already subscribed): $e');
      }
    });
  }

  void unsubscribe(String chatId) => _pusher.unsubscribe(channelName: chatId);

  void unsubscribeFromUserChannel(String userId) =>
      _pusher.unsubscribe(channelName: 'user-$userId');

  void disconnect() {
    _pusher.disconnect();
    _initialized = false;
  }
}
