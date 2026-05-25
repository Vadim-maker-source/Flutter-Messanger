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
    print('[PUSHER] init key=$_key cluster=$_cluster');
    await _pusher.init(
      apiKey: _key,
      cluster: _cluster,
      onConnectionStateChange: (cur, prev) =>
          print('[PUSHER] state $prev -> $cur'),
      onError: (msg, code, err) =>
          print('[PUSHER] error: $msg code=$code err=$err'),
      onSubscriptionSucceeded: (channelName, data) =>
          print('[PUSHER] subscribed to $channelName'),
      onSubscriptionError: (msg, e) =>
          print('[PUSHER] subscription error: $msg err=$e'),
      onEvent: (event) =>
          print('[PUSHER] event channel=${event.channelName} name=${event.eventName}'),
    );
    await _pusher.connect();
    print('[PUSHER] connect() called');
    _initialized = true;
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
        onEvent: (dynamic e) => onEvent(e as PusherEvent),
      );
    } catch (e) {
      print('[PUSHER] subscribe error ($channel): $e');
    }
  }

  // ─── Chat channel ────────────────────────────────────────────────────────────

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
    _sub(chatId, (event) {
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

  // ─── Presence (online status) ────────────────────────────────────────────────

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

  // ─── Sidebar channel (unread updates) ────────────────────────────────────────

  void subscribeToSidebar(
    String userId, {
    required void Function(String chatId, int unreadCount, Map<String, dynamic>? lastMessage) onUpdate,
  }) {
    _sub('sidebar-$userId', (event) {
      if (event.eventName != 'sidebar-update') return;
      final data = _parse(event.data);
      onUpdate(
        data['chatId']?.toString() ?? '',
        (data['unreadCount'] as num?)?.toInt() ?? 0,
        data['lastMessage'] as Map<String, dynamic>?,
      );
    });
  }

  // ─── User channel (calls) ────────────────────────────────────────────────────

  void subscribeToUserChannel(
    String userId, {
    required void Function(Map<String, dynamic>) onIncomingCall,
    required void Function(Map<String, dynamic>) onOutgoingCall,
    void Function(Map<String, dynamic>)? onWebRtcSignal,
  }) {
    print('[PUSHER] subscribeToUserChannel userId=$userId');
    _sub('user-$userId', (event) {
      print('[PUSHER] user-channel event=${event.eventName} data=${event.data}');
      final data = _parse(event.data);
      switch (event.eventName) {
        case 'incoming-call':
          print('[PUSHER] -> incoming-call');
          onIncomingCall(data);
        case 'outgoing-call':
          print('[PUSHER] -> outgoing-call');
          onOutgoingCall(data);
        case 'webrtc-signal':
          print('[PUSHER] -> webrtc-signal type=${data['type']}');
          onWebRtcSignal?.call(data);
      }
    });
  }

  // ─── Unsubscribe ─────────────────────────────────────────────────────────────

  void unsubscribe(String channel) => _pusher.unsubscribe(channelName: channel);
  void unsubscribeFromUserChannel(String userId) => unsubscribe('user-$userId');
  void unsubscribeFromPresence() => unsubscribe('presence');
  void unsubscribeFromSidebar(String userId) => unsubscribe('sidebar-$userId');

  void disconnect() {
    _pusher.disconnect();
    _initialized = false;
  }
}
