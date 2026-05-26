import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/chat_screen.dart';
import '../screens/call_screen.dart';
import '../models/chat.dart';
import '../main.dart';
import 'api_service.dart';

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
          channelDescription: 'Входящие звонки',
          importance: Importance.max,
          priority: Priority.max,
          // Пробивает экран блокировки и разворачивает activity в full-screen
          fullScreenIntent: true,
          // Помечает уведомление как "звонок" — Android отдаёт ему приоритет
          // (например, MIUI / OneUI знают что это звонок и обходят DnD).
          category: AndroidNotificationCategory.call,
          // Не свайпается, не закрывается тапом мимо
          ongoing: true,
          autoCancel: false,
          // Показываем содержимое полностью даже на lockscreen
          visibility: NotificationVisibility.public,
          // Звук + вибрация рингтона
          playSound: true,
          enableVibration: true,
          // Авто-закрытие через 45 сек если никто не ответит
          timeoutAfter: 45000,
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

  // Берём базовый URL из ApiService — чтобы при смене окружения (dev → prod)
  // достаточно было поправить одно место. Раньше тут был захардкожен Vercel.
  static String get _baseUrl => ApiService.baseUrl;

  static final _fcm = FirebaseMessaging.instance;
  static final _ln = FlutterLocalNotificationsPlugin();
  static GlobalKey<NavigatorState>? _navigatorKey;

  /// Стрим обновлений FCM-токена. Подписываемся в main.dart, чтобы при
  /// смене токена сразу пересохранять на сервере.
  static Stream<String> get onTokenRefresh => _fcm.onTokenRefresh;

  static Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;

    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    final androidPlugin =
        _ln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      msgChannelId, 'Сообщения',
      importance: Importance.high,
    ));
    // Канал звонков — особый: включаем все важные параметры (рингтон, вибро,
    // обход Do-Not-Disturb, light), чтобы UX был как у обычного телефона.
    // ВАЖНО: настройки канала фиксируются при первом создании. Чтобы их
    // переприменить — пользователь должен переустановить приложение или зайти
    // в системные настройки канала.
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      callChannelId, 'Звонки',
      description: 'Входящие звонки',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      showBadge: true,
    ));

    // Android 14+: для full-screen intent (поверх lockscreen) на некоторых
    // устройствах нужно явное разрешение пользователя. Запрашиваем при init.
    try {
      // POST_NOTIFICATIONS permission (Android 13+)
      final notifGranted = await androidPlugin?.requestNotificationsPermission();
      debugPrint('[NotificationService] notifications granted: $notifGranted');
    } catch (e) {
      debugPrint('[NotificationService] requestNotificationsPermission error: $e');
    }
    try {
      // USE_FULL_SCREEN_INTENT permission (Android 14+)
      final fullscreenGranted = await androidPlugin?.requestFullScreenIntentPermission();
      debugPrint('[NotificationService] full-screen intent granted: $fullscreenGranted');
      if (fullscreenGranted == false) {
        debugPrint(
          '[NotificationService] !!! Пользователь не дал full-screen intent. '
          'Звонок будет приходить как обычное уведомление, без разворота на весь экран. '
          'Для исправления: Настройки → Apps → Kyro → Уведомления → '
          '"Allow full-screen notifications" → включить.',
        );
      }
    } catch (e) {
      debugPrint('[NotificationService] requestFullScreenIntentPermission error: $e');
    }

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
      if (isCallSlotLocked()) return;
      lockCallSlot();
      Navigator.of(ctx).push(MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: data['callId'] ?? '',
          chatId: data['chatId'] ?? '',
          callType: data['callType'] ?? 'audio',
          isIncoming: true,
          callerName: data['callerName'] ?? '',
          chatName: data['chatName'] ?? 'Звонок',
        ),
      )).then((_) => unlockCallSlot());
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
