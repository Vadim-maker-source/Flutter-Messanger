import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_video_flutter/stream_video_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/call_screen.dart';
import 'services/api_service.dart';
import 'services/pusher_service_ws.dart';

// Глобальный navigatorKey для показа звонков поверх любого экрана
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Глобальный PusherService для звонков
final _callPusher = PusherService();
final _api = ApiService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru', null);
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
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Messenger',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'Nunito',
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: AppColors.surface,
          onSurface: Colors.white,
          onPrimary: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Nunito',
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          hintStyle: const TextStyle(color: AppColors.muted),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w600),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          tileColor: Colors.transparent,
          textColor: Colors.white,
          iconColor: AppColors.muted,
        ),
        dividerColor: AppColors.surfaceAlt,
        useMaterial3: true,
      ),
      home: const _Splash(),
    );
  }
}

class _Splash extends StatefulWidget {
  const _Splash();

  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> {
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final userId = prefs.getString('user_id');
    if (!mounted) return;

    if (token != null && userId != null) {
      await _initStreamAndCalls(userId);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
  }
}

/// Инициализирует Stream SDK и подписывается на Pusher-события звонков.
/// Вызывается после логина и при старте если уже авторизован.
bool _callsInitialized = false;

Future<void> _initStreamAndCalls(String userId) async {
  if (_callsInitialized) return;
  _callsInitialized = true;
  final tokenData = await _api.getStreamToken();
  if (tokenData == null) {
    print('[CALLS] getStreamToken returned null — check /calls/token endpoint');
    return;
  }

  final streamToken = tokenData['token'] as String;
  final apiKey = tokenData['apiKey'] as String;

  // Инициализируем Stream SDK
  final prefs = await SharedPreferences.getInstance();
  final displayName = prefs.getString('user_display_name') ?? userId;

  StreamVideo.reset(disconnect: false);
  StreamVideo(
    apiKey,
    user: User.regular(
      userId: userId,
      name: displayName,
    ),
    userToken: streamToken,
  );

  // Подписываемся на Pusher-события звонков
  _callPusher.subscribeToUserChannel(
    userId,
    onIncomingCall: (data) => _handleIncomingCall(data),
    onOutgoingCall: (data) => _handleOutgoingCall(data),
  );
}

bool _callScreenOpen = false;

void _handleIncomingCall(Map<String, dynamic> data) {
  print('[CALLS] incoming-call received: $data');
  if (_callScreenOpen) { print('[CALLS] screen already open, skipping'); return; }
  final callId = data['callId'] as String? ?? '';
  final type = data['type'] as String? ?? 'audio';
  final chatName = data['chatName'] as String? ?? 'Звонок';
  final from = data['from'] as Map<String, dynamic>? ?? {};
  final callerName = (from['displayName'] ?? from['username'] ?? 'Неизвестный') as String;

  _openCallScreen(
    callId: callId,
    callType: type,
    isIncoming: true,
    callerName: callerName,
    chatName: chatName,
  );
}

void _handleOutgoingCall(Map<String, dynamic> data) {
  print('[CALLS] outgoing-call received: $data');
  if (_callScreenOpen) { print('[CALLS] screen already open, skipping'); return; }
  final callId = data['callId'] as String? ?? '';
  final type = data['type'] as String? ?? 'audio';
  final chatName = data['chatName'] as String? ?? 'Звонок';

  _openCallScreen(
    callId: callId,
    callType: type,
    isIncoming: false,
    callerName: '',
    chatName: chatName,
  );
}

void _openCallScreen({
  required String callId,
  required String callType,
  required bool isIncoming,
  required String callerName,
  required String chatName,
}) {
  print('[CALLS] _openCallScreen callId=$callId ctx=${navigatorKey.currentContext}');
  _callScreenOpen = true;

  // Используем addPostFrameCallback чтобы гарантировать готовность контекста
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      print('[CALLS] context is null, cannot navigate');
      _callScreenOpen = false;
      return;
    }
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: callId,
          callType: callType,
          isIncoming: isIncoming,
          callerName: callerName,
          chatName: chatName,
        ),
      ),
    ).then((_) => _callScreenOpen = false);
  });
}

/// Вызывается из LoginScreen после успешного входа
Future<void> initCallsAfterLogin(String userId, String displayName) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('user_id', userId);
  await prefs.setString('user_display_name', displayName);
  await _initStreamAndCalls(userId);
}

/// Вызывается при выходе из аккаунта
void disposeCallsOnLogout(String userId) {
  _callPusher.unsubscribeFromUserChannel(userId);
  StreamVideo.reset(disconnect: true);
  _callsInitialized = false;
}
