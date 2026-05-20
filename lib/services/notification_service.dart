import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/chat_screen.dart';
import '../screens/call_screen.dart';
import '../models/chat.dart';

// ─── Top-level callbacks (required by flutter_local_notifications & FCM) ──────

/// FCM background handler — runs in a separate isolate.
/// Must NOT use Flutter UI (Navigator, BuildContext, etc.)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // flutter_local_notifications needs its own init in background isolate
  final ln = FlutterLocalNotificationsPlugin();
  await ln.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  await _showNotification(ln, message.data,
      title: message.notification?.title,
      body: message.notification?.body);
}

/// Background notification action callback — also top-level.
@pragma('vm:entry-point')
void onBackgroundNotificationAction(NotificationResponse r) {
  // Background actions that don't need UI (mark read) are handled here.
  // Navigation actions are ignored — user must open the app.
  if (r.actionId == NotificationService.actionRead && r.payload != null) {
    final data = jsonDecode(r.payload!) as Map<String, dynamic>;
    NotificationService.markReadStatic(data['chatId'] as String? ?? '');
  }
}

// ─── Shared show logic (used by both foreground and background) ───────────────

Future<void> _showNotification(
  FlutterLocalNotificationsPlugin ln,
  Map<String, dynamic> data, {
  String? title,
  String? body,
}) async {
  final t = title ?? data['title'] ?? '';
  final b = body ?? data['body'] ?? '';
  final payload = jsonEncode(data);

  if (data['type'] == 'call') {
    await ln.show(
      id: (data['callId'] ?? '').hashCode & 0x7FFFFFFF,
      title: t,
      body: b,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationService.callChannelId, 'Звонки',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
          actions: const [
            AndroidNotificationAction(NotificationService.actionAnswer, 'Ответить',
                showsUserInterface: true),
            AndroidNotificationAction(NotificationService.actionDecline, 'Отклонить'),
          ],
        ),
      ),
      payload: payload,
    );
  } else {
    await ln.show(
      id: (data['chatId'] ?? '').hashCode & 0x7FFFFFFF,
      title: t,
      body: b,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationService.msgChannelId, 'Сообщения',
          importance: Importance.high,
          priority: Priority.high,
          actions: const [
            AndroidNotificationAction(NotificationService.actionRead, 'Прочитано'),
          ],
        ),
      ),
      payload: payload,
    );
  }
}

// ─── NotificationService ──────────────────────────────────────────────────────

class NotificationService {
  static const msgChannelId = 'messages';
  static const callChannelId = 'calls';
  static const actionRead = 'mark_read';
  static const actionAnswer = 'answer_call';
  static const actionDecline = 'decline_call';
  static const _baseUrl = 'https://kyro-messanger.vercel.app/api/mobile';

  static final _fcm = FirebaseMessaging.instance;
  static final _ln = FlutterLocalNotificationsPlugin();
  static GlobalKey<NavigatorState>? _navigatorKey;

  static Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;

    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    final androidPlugin =
        _ln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      msgChannelId, 'Сообщения',
      importance: Importance.high,
    ));
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      callChannelId, 'Звонки',
      importance: Importance.max,
    ));

    await _ln.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: _onTap,
      onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationAction,
    );

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen((msg) => _showNotification(_ln, msg.data,
        title: msg.notification?.title, body: msg.notification?.body));
    FirebaseMessaging.onMessageOpenedApp.listen((msg) => _navigate(msg.data));

    final initial = await _fcm.getInitialMessage();
    if (initial != null) _navigate(initial.data);
  }

  static Future<String?> getToken() => _fcm.getToken();

  // ─── Foreground tap ──────────────────────────────────────────────────────────

  static void _onTap(NotificationResponse r) {
    if (r.payload == null) return;
    final data = jsonDecode(r.payload!) as Map<String, dynamic>;

    if (r.actionId == actionRead) {
      markReadStatic(data['chatId'] as String? ?? '');
      return;
    }
    if (r.actionId == actionDecline) return;

    _navigate(data);
  }

  // ─── Navigation ──────────────────────────────────────────────────────────────

  static void _navigate(Map<String, dynamic> data) {
    final ctx = _navigatorKey?.currentContext;
    if (ctx == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _navigate(data));
      return;
    }

    if (data['type'] == 'message') {
      Navigator.of(ctx).push(MaterialPageRoute(
        builder: (_) => ChatScreen(chat: Chat.stub(data['chatId'] ?? '')),
      ));
    } else if (data['type'] == 'call') {
      Navigator.of(ctx).push(MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: data['callId'] ?? '',
          callType: data['callType'] ?? 'audio',
          isIncoming: true,
          callerName: data['callerName'] ?? '',
          chatName: data['chatName'] ?? 'Звонок',
        ),
      ));
    }
  }

  // ─── Mark read ───────────────────────────────────────────────────────────────

  static Future<void> markReadStatic(String chatId) async {
    if (chatId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) return;
      await http.post(
        Uri.parse('$_baseUrl/messages/read'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'chatId': chatId}),
      );
    } catch (_) {}
  }
}
