import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/call_screen.dart';
import 'screens/share_chat_picker.dart';
import 'screens/user_profile_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/pusher_service_ws.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final callPusher = PusherService();
final apiService = ApiService();

typedef SignalCallback = void Function(Map<String, dynamic>);
SignalCallback? onSignal;
final List<Map<String, dynamic>> signalBuffer = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru', null);
  // Firebase нужен для FCM (фоновые пуши о звонках/сообщениях). Если init падает —
  // приложение продолжит работать в foreground через Pusher, но push'и не пойдут.
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await NotificationService.init(navigatorKey);
  } catch (e) {
    debugPrint('[MAIN] Firebase/Notifications init failed: $e');
  }
  runApp(const MyApp());
}

class AppColors {
  static const primary = Color(0xFF6C3EF4);
  static const secondary = Color(0xFFB98CFF);
  static const darkAccent = Color(0xFF4B1FD1);
  static const background = Color(0xFF09090B);
  static const surface = Color(0xFF18181B);
  static const surfaceAlt = Color(0xFF27272A);
  static const border = Color(0xFF3F3F46);
  static const muted = Color(0xFF71717A);
  static const scrollbar = Color(0xFF7166D8);
  static const searchbar = Color(0xFF27272A);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override Widget build(BuildContext context) {
    return MaterialApp(title: 'Messenger', debugShowCheckedModeBanner: false, navigatorKey: navigatorKey,
      theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: AppColors.background, fontFamily: 'Nunito',
        colorScheme: const ColorScheme.dark(primary: AppColors.primary, secondary: AppColors.secondary, surface: AppColors.surface, onSurface: Colors.white, onPrimary: Colors.white),
        appBarTheme: const AppBarTheme(backgroundColor: AppColors.background, elevation: 0, titleTextStyle: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Nunito'), iconTheme: IconThemeData(color: Colors.white)),
        inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: AppColors.surfaceAlt, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)), hintStyle: const TextStyle(color: AppColors.muted)),
        elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), textStyle: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w600))),
        listTileTheme: const ListTileThemeData(tileColor: Colors.transparent, textColor: Colors.white, iconColor: AppColors.muted), dividerColor: AppColors.surfaceAlt, useMaterial3: true),
      home: const _Splash());
  }
}

class _Splash extends StatefulWidget { const _Splash(); @override State<_Splash> createState() => _SplashState(); }
class _SplashState extends State<_Splash> {
  static const _channel = MethodChannel('app.channel.shared.data');

  @override void initState() {
    super.initState();
    _channel.setMethodCallHandler(_onChannelCall);
    _check();
    _checkShareIntent();
  }

  /// Обработчик «горячих» share-intent'ов и deep-link'ов — когда приложение
  /// уже запущено, а из системного меню пришёл новый share или ссылка.
  /// MainActivity.onNewIntent вызовет `onNewSharedData` с готовым payload.
  Future<dynamic> _onChannelCall(MethodCall call) async {
    if (call.method == 'onNewSharedData') {
      final args = (call.arguments as Map?) ?? {};
      final profileId = args['profileId'] as String?;
      final text = args['text'] as String?;
      final files = (args['files'] as List?)?.cast<String>();

      if (profileId != null && profileId.isNotEmpty) {
        _openProfile(profileId);
        return null;
      }

      _openSharePicker(text: text, files: files);
    }
    return null;
  }

  /// Проверяем, не запустили ли нас через «Поделиться» или deep-link
  /// (профиль пользователя) из другого приложения.
  /// Native-код в MainActivity сохраняет текст, пути к файлам и profileId,
  /// мы их забираем единым вызовом `consumeSharedData`.
  Future<void> _checkShareIntent() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'consumeSharedData');
      if (result == null) return;
      final profileId = result['profileId'] as String?;
      final text = result['text'] as String?;
      final filesRaw = result['files'] as List?;

      if (profileId != null && profileId.isNotEmpty) {
        _openProfile(profileId);
        return;
      }

      _openSharePicker(text: text, files: filesRaw?.cast<String>());
    } on MissingPluginException {
      // Native сторона не реализована — пропускаем
    } catch (_) {}
  }

  /// Открывает профиль пользователя по ID, полученному из deep-link.
  void _openProfile(String userId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      Navigator.of(ctx).push(MaterialPageRoute(
        builder: (_) => UserProfileScreen(userId: userId),
      ));
    });
  }

  void _openSharePicker({String? text, List<String>? files}) {
    final hasText = text != null && text.isNotEmpty;
    final hasFiles = files != null && files.isNotEmpty;
    if (!hasText && !hasFiles) return;

    final sharedFiles = (files ?? const <String>[])
        .map((p) => File(p))
        .where((f) => f.existsSync())
        .toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      Navigator.of(ctx).push(MaterialPageRoute(
        builder: (_) => ShareChatPicker(
          sharedText: hasText ? text : null,
          sharedFiles: sharedFiles.isNotEmpty ? sharedFiles : null,
        ),
      ));
    });
  }

  Future<void> _check() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token'); final userId = prefs.getString('user_id');
    if (!mounted) return;
    if (token != null && userId != null) { await _init(userId); if (!mounted) return; Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen())); }
    else Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
}

bool _initDone = false;
StreamSubscription<String>? _fcmTokenSub;

Future<void> _init(String userId) async {
  if (_initDone) return; _initDone = true;
  callPusher.subscribeToUserChannel(userId,
    onIncomingCall: _onIn,
    onOutgoingCall: _onOut,
    onWebRtcSignal: (data) { signalBuffer.add(data); onSignal?.call(data); },
  );
  // Регистрируем текущий FCM-токен на сервере, чтобы прилетали push'и о
  // входящих звонках/сообщениях когда приложение в фоне или убито.
  // Делается это _после_ Pusher subscribe — чтобы получить дубль через push
  // только если Pusher по какой-то причине не доставил (фон/Doze).
  unawaited(_registerFcmToken());
  // Токен может протухнуть — переподписываемся на refresh один раз за сессию.
  _fcmTokenSub ??= NotificationService.onTokenRefresh.listen((t) {
    debugPrint('[MAIN] FCM token refreshed → re-registering');
    apiService.saveFcmToken(t);
  });
}

Future<void> _registerFcmToken() async {
  try {
    final token = await NotificationService.getToken();
    if (token == null || token.isEmpty) {
      debugPrint('[MAIN] FCM token is null — push не работает');
      return;
    }
    debugPrint('[MAIN] FCM token: ${token.substring(0, 20)}...');
    await apiService.saveFcmToken(token);
  } catch (e) {
    debugPrint('[MAIN] saveFcmToken error: $e');
  }
}

bool _open = false;

// Called from chat_screen before API call to lock the slot
void lockCallSlot() { _open = true; }
void unlockCallSlot() { _open = false; }
bool isCallSlotLocked() => _open;

void _onIn(Map<String, dynamic> d) {
  if (_open) return;
  final cid = d['callId'] as String? ?? '';
  final ct = d['type'] as String? ?? 'audio';
  final cn = d['chatName'] as String? ?? '';
  final from = d['from'] as Map<String, dynamic>? ?? {};
  final caller = (from['displayName'] ?? from['username'] ?? '') as String;
  final chatId = d['chatId'] as String? ?? '';
  _nav(cid, chatId, ct, true, caller, cn);
}

void _onOut(Map<String, dynamic> d) {
  // If _open is already true, the outgoing call was started from chat_screen
  // and CallScreen is already open — ignore this Pusher echo.
  if (_open) return;
  final cid = d['callId'] as String? ?? '';
  final ct = d['type'] as String? ?? 'audio';
  final cn = d['chatName'] as String? ?? '';
  final chatId = d['chatId'] as String? ?? '';
  _nav(cid, chatId, ct, false, '', cn);
}

void _nav(String cid, String chatId, String ct, bool inc, String caller, String cn) {
  _open = true;
  final ctx = navigatorKey.currentContext;
  if (ctx == null) { _open = false; return; }
  Navigator.of(ctx).push(MaterialPageRoute(
    builder: (_) => CallScreen(callId: cid, chatId: chatId, callType: ct, isIncoming: inc, callerName: caller, chatName: cn),
  )).then((_) => _open = false);
}

Future<void> initCallsAfterLogin(String userId, String displayName) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('user_id', userId); await prefs.setString('user_display_name', displayName);
  await _init(userId);
}
void disposeCallsOnLogout(String userId) { callPusher.unsubscribeFromUserChannel(userId); _initDone = false; }
