import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../main.dart';

class CallScreen extends StatefulWidget {
  final String callId, chatId, callType, callerName, chatName;
  final bool isIncoming;
  const CallScreen({
    super.key,
    required this.callId,
    required this.chatId,
    required this.callType,
    required this.isIncoming,
    required this.callerName,
    required this.chatName,
  });
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _local, _remote;

  bool _connecting = false, _connected = false, _left = false;
  bool _muted = false, _vidOff = false;
  // 'none' | 'peer-left' | 'lost'
  String _endReason = 'none';
  bool _hasEverConnected = false;

  Timer? _timeoutTimer, _durationTimer;
  Timer? _disconnectGraceTimer; // grace period for transient disconnects
  Timer? _iceRestartTimer;      // delayed ICE restart on failure
  int _durationSecs = 0;
  int _iceRestartAttempts = 0;
  static const _maxIceRestartAttempts = 3;
  // Grace period before treating ICE/connection drop as lost. Web is given enough
  // time to recover networks, switch transports, etc.
  static const _disconnectGraceSec = 15;

  Map<String, dynamic>? _pendingOffer;
  final _pendingIce = <Map<String, dynamic>>[];
  bool _remoteDescSet = false;
  // Время старта экрана (для защиты от ложных «peer-left» в первые секунды)
  final DateTime _startedAt = DateTime.now();
  bool _localOfferSent = false;
  bool _localAnswerSent = false;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  bool get _isVideo => widget.callType == 'video';
  bool get _isCaller => !widget.isIncoming;
  // Сколько прошло с момента создания экрана.
  int get _elapsedSec => DateTime.now().difference(_startedAt).inSeconds;
  // Звонок ещё в фазе инициализации — защита от преждевременных «peer-left».
  bool get _initialPhase => !_hasEverConnected && _elapsedSec < 8;

  // ICE configuration fallback. Реальные TURN-креды получаем с сервера через
  // /api/mobile/calls/ice-config (читается из .env). Этот fallback — только
  // STUN, и его достаточно для NAT-ов с обычным cone-маппингом, но для
  // симметричного NAT TURN обязателен.
  static const _iceFallback = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'iceCandidatePoolSize': 2,
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require',
    'sdpSemantics': 'unified-plan',
  };

  // Текущий используемый ICE-конфиг. Заполняется в _start() из API; до этого —
  // fallback. Если до создания PeerConnection конфиг ещё не подгрузился —
  // PC создаётся с fallback (звонок может работать в LAN/cone NAT).
  Map<String, dynamic> _iceConfig = Map<String, dynamic>.from(_iceFallback);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _start();
  }

  Future<void> _start() async {
    debugPrint('[CALL] _start callId=${widget.callId} type=${widget.callType} '
        'incoming=${widget.isIncoming}');
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    // Загружаем актуальный ICE-конфиг с сервера. Делаем это рано — до создания
    // PeerConnection. Если запрос упал — остаёмся с fallback (STUN-only).
    try {
      final fetched = await _api.fetchIceConfig();
      if (fetched != null && !_left) {
        _iceConfig = fetched;
        debugPrint('[CALL] ICE config loaded: ${(fetched['iceServers'] as List).length} servers');
      } else {
        debugPrint('[CALL] ICE config fetch failed — using STUN-only fallback');
      }
    } catch (e) {
      debugPrint('[CALL] ICE config fetch error: $e — using fallback');
    }
    if (_left) return;

    // Сначала ставим callback, потом снимаем буфер — чтобы между этими операциями
    // ни один сигнал не потерялся.
    onSignal = (s) { if (!_left) handleSignal(s); };
    final buffered = List<Map<String, dynamic>>.from(signalBuffer);
    signalBuffer.clear();
    if (buffered.isNotEmpty) {
      debugPrint('[CALL] draining ${buffered.length} buffered signals');
    }
    for (final s in buffered) {
      handleSignal(s);
    }

    if (!widget.isIncoming) {
      _beginOutgoing();
    } else {
      // Если offer не пришёл через Pusher — забираем с сервера
      if (_pendingOffer == null) {
        debugPrint('[CALL] no offer yet — fetching from server');
        final sdp = await _api.fetchOffer(widget.callId);
        if (sdp != null && _pendingOffer == null && !_left) {
          debugPrint('[CALL] got offer from server (${sdp.length} bytes)');
          handleSignal({'type': 'offer', 'sdp': sdp});
        }
      }
      // Pre-warm media so Accept is instant
      _getMedia().then((s) async {
        if (_left) {
          for (final t in (s?.getTracks() ?? const [])) {
            try { t.stop(); } catch (_) {}
          }
          try { await s?.dispose(); } catch (_) {}
          return;
        }
        if (s != null) {
          _local = s;
          try { _localRenderer.srcObject = s; } catch (_) {}
          if (mounted) setState(() {});
        }
      });
    }
  }

  // ─── Media ────────────────────────────────────────────────────────────────────

  Future<MediaStream?> _getMedia() async {
    if (_isVideo) {
      // Каскад попыток от лучшего к худшему — getUserMedia вернёт первое что
      // удалось. На современных чипах (Snapdragon 7+, Dimensity 8000+) пройдёт
      // 1080p@60. На средних — 1080p@30. На бюджетных — 720p. На совсем
      // дровах — 480p.
      for (final cfg in [
        {'audio': true, 'video': {'width': 1920, 'height': 1080, 'frameRate': 60, 'facingMode': 'user'}},
        {'audio': true, 'video': {'width': 1920, 'height': 1080, 'frameRate': 30, 'facingMode': 'user'}},
        {'audio': true, 'video': {'width': 1280, 'height': 720, 'frameRate': 60, 'facingMode': 'user'}},
        {'audio': true, 'video': {'width': 1280, 'height': 720, 'frameRate': 30, 'facingMode': 'user'}},
        {'audio': true, 'video': {'width': 640, 'height': 480, 'frameRate': 30, 'facingMode': 'user'}},
        {'audio': true, 'video': true},
      ]) {
        try {
          final stream = await navigator.mediaDevices.getUserMedia(cfg as Map<String, dynamic>);
          final track = stream.getVideoTracks().firstOrNull;
          debugPrint('[CALL] getUserMedia OK: ${cfg['video']} → track=${track?.label}');
          return stream;
        } catch (_) {}
      }
    }
    try { return await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false}); } catch (_) {}
    return null;
  }

  // Применяем максимальные битрейты к sender'ам PC. Вызывается ПОСЛЕ
  // setLocalDescription. Без этого WebRTC по дефолту шлёт ~1 Мбит/с видео,
  // что выглядит как блюр на 720p+.
  static const _videoMaxBitrate = 6000000;  // 6 Mbps — отличное 1080p@60fps на топовых чипах
  static const _audioMaxBitrate = 128000;   // 128 kbps — HD voice через Opus

  /// Munge SDP: включаем у Opus стерео + FEC + макс. sample rate. Безопасное
  /// вмешательство — только параметры существующего m=audio, не codec
  /// preference и не структура SDP. Эффект слышен сразу — голос «пухлее»,
  /// меньше "квакает" при потерях пакетов.
  String _tuneSdp(String sdp) {
    final fmtpRegex = RegExp(r'a=fmtp:111 ([^\r\n]*)');
    return sdp.replaceAllMapped(fmtpRegex, (m) {
      final params = m.group(1) ?? '';
      bool has(String k) => RegExp('(^|;)\\s*$k=').hasMatch(params);
      final additions = <String>[];
      if (!has('stereo'))           additions.add('stereo=1');
      if (!has('sprop-stereo'))     additions.add('sprop-stereo=1');
      if (!has('maxaveragebitrate'))additions.add('maxaveragebitrate=$_audioMaxBitrate');
      if (!has('maxplaybackrate'))  additions.add('maxplaybackrate=48000');
      if (!has('useinbandfec'))     additions.add('useinbandfec=1');
      if (!has('usedtx'))           additions.add('usedtx=0');
      final sep = params.trim().endsWith(';') || params.trim().isEmpty ? '' : ';';
      return 'a=fmtp:111 $params$sep${additions.join(";")}';
    });
  }

  Future<void> _tuneSenders(RTCPeerConnection pc) async {
    try {
      final senders = await pc.getSenders();
      for (final sender in senders) {
        final track = sender.track;
        if (track == null) continue;
        try {
          final params = sender.parameters;
          if (params.encodings == null || params.encodings!.isEmpty) {
            params.encodings = [RTCRtpEncoding()];
          }
          if (track.kind == 'video') {
            params.encodings![0].maxBitrate = _videoMaxBitrate;
            params.encodings![0].maxFramerate = 60;
            params.degradationPreference = RTCDegradationPreference.MAINTAIN_FRAMERATE;
          } else if (track.kind == 'audio') {
            params.encodings![0].maxBitrate = _audioMaxBitrate;
          }
          await sender.setParameters(params);
        } catch (e) {
          debugPrint('[CALL] tune sender error: $e');
        }
      }
    } catch (e) {
      debugPrint('[CALL] _tuneSenders error: $e');
    }
  }

  // ─── PeerConnection ───────────────────────────────────────────────────────────

  Future<RTCPeerConnection?> _createPC(MediaStream? stream) async {
    try {
      final pc = await createPeerConnection(_iceConfig);
      if (_left) { pc.close(); return null; }

      // Добавляем треки до createOffer/createAnswer (unified-plan).
      if (stream != null) {
        for (final t in stream.getTracks()) {
          await pc.addTrack(t, stream);
        }
      }

      pc.onIceCandidate = (c) {
        if (!_left && (c.candidate?.isNotEmpty ?? false)) {
          _sendSignal('ice-candidate', {
            'candidate': c.candidate,
            'sdpMLineIndex': c.sdpMLineIndex,
            'sdpMid': c.sdpMid,
          });
        }
      };

      pc.onTrack = (e) {
        if (_left || !mounted) return;
        if (e.streams.isEmpty) return;
        final stream = e.streams[0];
        _remote = stream;
        try { _remoteRenderer.srcObject = stream; } catch (_) {}
        if (mounted) setState(() {});
      };

      pc.onConnectionState = (s) {
        if (_left) return;
        debugPrint('[CALL] connection state: $s');
        switch (s) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _onPeerConnected();
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            // Transient state — ждём grace period; если не восстановится,
            // попробуем ICE restart, и только в случае Failed реально завершим.
            _onTransientDisconnect();
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
            _onConnectionFailed();
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
            // Не интерпретируем как уход — close может быть инициирован нами.
            // Реальный «peer-left» приходит только через сигнал 'call-ended'.
            break;
          default:
            break;
        }
      };

      pc.onIceConnectionState = (s) {
        if (_left) return;
        debugPrint('[CALL] ice state: $s');
        if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _onPeerConnected();
        } else if (s == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          _onTransientDisconnect();
        } else if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          _onConnectionFailed();
        }
      };

      return pc;
    } catch (e) {
      debugPrint('[CALL] _createPC error: $e');
      return null;
    }
  }

  // Соединение установлено / восстановлено
  void _onPeerConnected() {
    if (_left || !mounted) return;
    _disconnectGraceTimer?.cancel(); _disconnectGraceTimer = null;
    _iceRestartTimer?.cancel(); _iceRestartTimer = null;
    _timeoutTimer?.cancel();
    _iceRestartAttempts = 0;
    final wasConnected = _connected;
    _connected = true;
    _connecting = false;
    _hasEverConnected = true;
    // Сбросить состояние «звонок закончен», если были в transient disconnect
    if (_endReason != 'none') _endReason = 'none';
    if (_durationTimer == null && !wasConnected) {
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _durationSecs++);
      });
    }
    setState(() {});
  }

  // Кратковременная потеря — даём шанс восстановиться сами или через ICE restart
  void _onTransientDisconnect() {
    if (_left || !mounted) return;
    if (!_hasEverConnected) return; // ещё не успели соединиться — это initial fail
    if (_disconnectGraceTimer?.isActive ?? false) return;
    debugPrint('[CALL] transient disconnect — grace ${_disconnectGraceSec}s');
    // Через половину grace-периода пробуем ICE restart (только caller).
    _iceRestartTimer?.cancel();
    _iceRestartTimer = Timer(const Duration(seconds: 4), () {
      if (!_left && _pc != null) _tryIceRestart();
    });
    _disconnectGraceTimer = Timer(const Duration(seconds: _disconnectGraceSec), () {
      if (_left) return;
      // Если за grace не вернулись в Connected — считаем потерянным
      final st = _pc?.connectionState;
      if (st == RTCPeerConnectionState.RTCPeerConnectionStateConnected) return;
      _markLostAndLeave();
    });
  }

  void _onConnectionFailed() {
    if (_left || !mounted) return;
    debugPrint('[CALL] connection failed — try ICE restart ($_iceRestartAttempts/$_maxIceRestartAttempts)');
    // В начальной фазе ещё нет смысла agressively завершать — handshake может
    // занять время особенно через TURN. Просто стартуем ICE restart и ждём
    // дольше (не помечаем как «lost» сразу).
    if (_iceRestartAttempts < _maxIceRestartAttempts) {
      _tryIceRestart();
      // В initialPhase даём 2x grace; иначе обычный grace.
      final grace = _initialPhase ? _disconnectGraceSec * 2 : _disconnectGraceSec;
      _disconnectGraceTimer?.cancel();
      _disconnectGraceTimer = Timer(Duration(seconds: grace), () {
        if (_left) return;
        final st = _pc?.connectionState;
        if (st == RTCPeerConnectionState.RTCPeerConnectionStateConnected) return;
        // Если ещё в initial phase — не помечаем «lost», только следующий
        // restart attempt; рестарт сам себя по таймеру не вызывает, поэтому
        // делаем явный второй вызов через короткое время.
        if (!_hasEverConnected && _iceRestartAttempts < _maxIceRestartAttempts) {
          _onConnectionFailed();
        } else {
          _markLostAndLeave();
        }
      });
    } else {
      _markLostAndLeave();
    }
  }

  void _markLostAndLeave() {
    if (_left || !mounted) return;
    setState(() {
      _connected = false;
      _endReason = _hasEverConnected ? 'lost' : 'lost';
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_left) _leave();
    });
  }

  Future<void> _tryIceRestart() async {
    if (_left || _pc == null) return;
    _iceRestartAttempts++;
    try {
      // Только caller инициирует новый offer с iceRestart:true.
      if (_isCaller) {
        final offer = await _pc!.createOffer({'iceRestart': true});
        await _pc!.setLocalDescription(offer);
        await _sendSignal('offer', {'sdp': offer.sdp});
        debugPrint('[CALL] sent ICE-restart offer');
      } else {
        // Callee может попросить caller перезапустить ICE через спец-сигнал, либо
        // просто выполнить restartIce() (заставит каноничным образом отправить
        // новые ICE candidates через onIceCandidate, если ICE согласован).
        _pc!.restartIce();
      }
    } catch (e) {
      debugPrint('[CALL] ICE restart failed: $e');
    }
  }

  // ─── Outgoing ─────────────────────────────────────────────────────────────────

  Future<void> _beginOutgoing() async {
    if (_connecting || _left) return;
    setState(() => _connecting = true);
    final stream = await _getMedia();
    if (_left) return;
    if (stream != null) { _local = stream; _localRenderer.srcObject = stream; }
    final pc = await _createPC(stream);
    if (_left || pc == null) { setState(() => _connecting = false); return; }
    _pc = pc;
    final offer = await pc.createOffer({});
    final tunedOffer = RTCSessionDescription(_tuneSdp(offer.sdp ?? ''), offer.type);
    await pc.setLocalDescription(tunedOffer);
    await _tuneSenders(pc);
    if (_left) return;
    await _sendSignal('offer', {'sdp': tunedOffer.sdp});
    _localOfferSent = true;
    debugPrint('[CALL] outgoing offer sent (callId=${widget.callId})');
    _timeoutTimer = Timer(const Duration(seconds: 60), () {
      if (!_left && !_connected && mounted) {
        setState(() { _connecting = false; _endReason = 'lost'; });
        Future.delayed(const Duration(seconds: 2), () { if (mounted && !_left) _leave(); });
      }
    });
  }

  // ─── Accept incoming ──────────────────────────────────────────────────────────

  Future<void> _join() async {
    if (_connecting || _left) return;
    setState(() => _connecting = true);
    // Если offer всё ещё не получен — забираем с сервера
    if (_pendingOffer == null) {
      final sdp = await _api.fetchOffer(widget.callId);
      if (sdp != null && _pendingOffer == null && !_left) {
        _pendingOffer = {'type': 'offer', 'sdp': sdp};
      }
    }
    // Reuse pre-fetched media if available, otherwise fetch now
    if (_local == null) {
      final stream = await _getMedia();
      if (_left) return;
      if (stream != null) { _local = stream; _localRenderer.srcObject = stream; }
    }
    final pc = await _createPC(_local);
    if (_left || pc == null) { setState(() => _connecting = false); return; }
    _pc = pc;
    if (_pendingOffer != null) {
      final po = _pendingOffer!; _pendingOffer = null;
      await _processOffer(po);
    }
    _timeoutTimer = Timer(const Duration(seconds: 60), () {
      if (!_left && !_connected && mounted) {
        setState(() { _connecting = false; _endReason = 'lost'; });
        Future.delayed(const Duration(seconds: 2), () { if (mounted && !_left) _leave(); });
      }
    });
  }

  // ─── Signal handling ──────────────────────────────────────────────────────────

  void handleSignal(Map<String, dynamic> s) {
    if (_left) return;
    switch (s['type']) {
      case 'offer': _onOffer(s); break;
      case 'answer': _onAnswer(s); break;
      case 'ice-candidate': _onIce(s); break;
      case 'call-ended':
        // Защита от ложных/эхо-сигналов: если мы ещё ни разу не были соединены
        // и прошло мало времени с открытия экрана — это, скорее всего, эхо
        // предыдущего звонка или преждевременный сигнал. Игнорируем.
        if (_initialPhase && !_localOfferSent && !_localAnswerSent) {
          debugPrint('[CALL] ignoring call-ended in initial phase '
              '(elapsed=${_elapsedSec}s, connected=$_hasEverConnected)');
          return;
        }
        debugPrint('[CALL] received call-ended — peer left');
        if (mounted) {
          setState(() {
            _endReason = 'peer-left';
            _connected = false;
          });
        }
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && !_left) _leave();
        });
        break;
    }
  }

  void _onOffer(Map<String, dynamic> s) {
    if (_pc == null) { _pendingOffer = s; return; }
    _processOffer(s);
  }

  Future<void> _processOffer(Map<String, dynamic> s) async {
    final sdp = s['sdp'] as String?; if (sdp == null || _pc == null) return;
    try {
      // Может быть второй offer (ICE restart).
      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      _remoteDescSet = true;
      final answer = await _pc!.createAnswer({});
      final tunedAnswer = RTCSessionDescription(_tuneSdp(answer.sdp ?? ''), answer.type);
      await _pc!.setLocalDescription(tunedAnswer);
      await _tuneSenders(_pc!);
      await _sendSignal('answer', {'sdp': tunedAnswer.sdp});
      _localAnswerSent = true;
      debugPrint('[CALL] answer sent (callId=${widget.callId})');
      await _flushPendingIce();
    } catch (e) {
      debugPrint('[CALL] _processOffer error: $e');
    }
  }

  Future<void> _onAnswer(Map<String, dynamic> s) async {
    final sdp = s['sdp'] as String?; if (sdp == null || _pc == null) return;
    try {
      final st = _pc!.signalingState;
      // Игнорируем answer, если мы уже в stable (например, повтор после ICE
      // restart, когда мы всё ещё в have-local-offer — обработать нужно).
      if (st == RTCSignalingState.RTCSignalingStateStable && _remoteDescSet) {
        debugPrint('[CALL] ignoring answer in stable state');
        return;
      }
      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      _remoteDescSet = true;
      await _flushPendingIce();
    } catch (e) {
      debugPrint('[CALL] _onAnswer error: $e');
    }
  }

  void _onIce(Map<String, dynamic> s) {
    if (_pc == null || !_remoteDescSet) {
      _pendingIce.add(s);
      return;
    }
    _processIce(s);
  }

  Future<void> _processIce(Map<String, dynamic> s) async {
    final c = s['candidate'] as String?;
    if (c == null || c.isEmpty) return;
    final mid = s['sdpMid'] as String?;
    final idx = (s['sdpMLineIndex'] as num?)?.toInt() ?? 0;
    try {
      await _pc?.addCandidate(RTCIceCandidate(c, mid, idx));
    } catch (e) {
      debugPrint('[CALL] addCandidate error: $e');
    }
  }

  Future<void> _flushPendingIce() async {
    final list = List<Map<String, dynamic>>.from(_pendingIce);
    _pendingIce.clear();
    for (final ice in list) {
      await _processIce(ice);
    }
  }

  Future<void> _sendSignal(String type, Map<String, dynamic> data) async {
    try {
      final token = await _api.getToken(); if (token == null) return;
      await http.post(Uri.parse('${ApiService.baseUrl}/calls/webrtc/signal'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({...data, 'type': type, 'callId': widget.callId}));
    } catch (e) {
      debugPrint('[CALL] _sendSignal($type) error: $e');
    }
  }

  /// Безопасно отсоединяет коллбэки и закрывает PeerConnection.
  /// Native callbacks могут приходить из потока WebRTC, поэтому коллбэки
  /// обнуляются ДО close, чтобы они не сработали уже после освобождения
  /// связанных объектов (что приводит к JNI-крашам в libjingle).
  Future<void> _disposePc() async {
    final pc = _pc;
    _pc = null;
    if (pc == null) return;
    try {
      pc.onIceCandidate = null;
      pc.onTrack = null;
      pc.onAddStream = null;
      pc.onRemoveStream = null;
      pc.onConnectionState = null;
      pc.onIceConnectionState = null;
      pc.onIceGatheringState = null;
      pc.onSignalingState = null;
      pc.onRenegotiationNeeded = null;
      pc.onDataChannel = null;
    } catch (_) {}
    try { await pc.close(); } catch (_) {}
    try { await pc.dispose(); } catch (_) {}
  }

  /// Останавливает треки и dispose'ит MediaStream.
  Future<void> _disposeStream(MediaStream? s, {bool stopTracks = true}) async {
    if (s == null) return;
    if (stopTracks) {
      for (final t in s.getTracks()) {
        try { await t.stop(); } catch (_) {}
      }
    }
    try { await s.dispose(); } catch (_) {}
  }

  bool _renderersDisposed = false;
  Future<void> _disposeRenderers() async {
    if (_renderersDisposed) return;
    _renderersDisposed = true;
    // Отсоединяем srcObject ДО dispose рендереров, чтобы не было обращения
    // к уже остановленным/освобождённым stream'ам из native renderer.
    try { _localRenderer.srcObject = null; } catch (_) {}
    try { _remoteRenderer.srcObject = null; } catch (_) {}
    try { await _localRenderer.dispose(); } catch (_) {}
    try { await _remoteRenderer.dispose(); } catch (_) {}
  }

  Future<void> _leave() async {
    if (_left) return; _left = true;
    _timeoutTimer?.cancel();
    _durationTimer?.cancel();
    _disconnectGraceTimer?.cancel();
    _iceRestartTimer?.cancel();
    onSignal = null;

    // Пересылаем call-ended ТОЛЬКО если мы инициировали выход (не из-за того,
    // что peer прислал call-ended нам — это приведёт к «эху»).
    if (_endReason != 'peer-left') {
      try { await _sendSignal('call-ended', {}); } catch (_) {}
    }

    // Порядок очистки важен:
    // 1) Отвязать srcObject у renderer'ов, чтобы они не дёргали native frames
    //    из освобождаемых stream'ов.
    try { _localRenderer.srcObject = null; } catch (_) {}
    try { _remoteRenderer.srcObject = null; } catch (_) {}

    // 2) Снять обработчики и закрыть PC. После этого native WebRTC поток
    //    больше не вызывает Dart callbacks.
    await _disposePc();

    // 3) Остановить и dispose локальный stream (мы его создали).
    final local = _local; _local = null;
    await _disposeStream(local, stopTracks: true);

    // 4) Remote stream приходит от другой стороны — треки stop'ить нельзя
    //    (они и так закроются с close PC), но dispose обертки можно.
    final remote = _remote; _remote = null;
    await _disposeStream(remote, stopTracks: false);

    // 5) Pop экран. dispose() State'а уже не будет дублировать очистку
    //    (флаги _left и _renderersDisposed предотвращают это).
    if (mounted) {
      Navigator.of(context).pop('ended');
    } else {
      // Если виджет уже unmounted, рендереры почистим вручную
      await _disposeRenderers();
    }
  }

  void _toggleMute() {
    final audio = _local?.getAudioTracks();
    if (audio == null) return;
    for (final t in audio) { t.enabled = _muted; }
    setState(() => _muted = !_muted);
  }

  void _toggleVideo() {
    final video = _local?.getVideoTracks();
    if (video == null) return;
    for (final t in video) { t.enabled = _vidOff; }
    setState(() => _vidOff = !_vidOff);
  }

  Future<void> _switchCamera() async {
    final vt = _local?.getVideoTracks().firstOrNull;
    if (vt == null) return;
    try { await Helper.switchCamera(vt); } catch (_) {}
  }

  String get _durationLabel {
    final m = _durationSecs ~/ 60; final s = _durationSecs % 60;
    return '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
  }

  @override
  void dispose() {
    _left = true;
    _timeoutTimer?.cancel();
    _durationTimer?.cancel();
    _disconnectGraceTimer?.cancel();
    _iceRestartTimer?.cancel();
    _pulseCtrl.dispose();
    onSignal = null;

    // Async cleanup. Не блокируем dispose() (он синхронный).
    // Если _leave() уже выполнился, _pc/_local/_remote = null, и эти вызовы
    // быстро выйдут.
    () async {
      // Сначала отвязываем srcObject, чтобы native renderer не обращался
      // к освобождаемым stream'ам.
      try { _localRenderer.srcObject = null; } catch (_) {}
      try { _remoteRenderer.srcObject = null; } catch (_) {}
      await _disposePc();
      final local = _local; _local = null;
      await _disposeStream(local, stopTracks: true);
      final remote = _remote; _remote = null;
      await _disposeStream(remote, stopTracks: false);
      await _disposeRenderers();
    }();

    super.dispose();
  }

  // ─── UI ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0E),
      body: Stack(children: [
        // Remote video fullscreen
        if (_remote != null && _endReason == 'none')
          Positioned.fill(child: RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)),

        // Gradient overlays
        Positioned.fill(child: Column(children: [
          Container(height: 130, decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xCC000000), Colors.transparent]))),
          const Spacer(),
          Container(height: 180, decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xCC000000), Colors.transparent]))),
        ])),

        // Content
        SafeArea(child: Column(children: [
          _buildTopBar(),
          const Spacer(),
          if (_endReason != 'none') _buildEndedOverlay()
          else if (widget.isIncoming && !_connecting && !_connected) _buildIncomingRing()
          else if (!widget.isIncoming && !_connected) _buildCallingOverlay()
          else if (_connected) _buildConnectedInfo(),
          const SizedBox(height: 20),
          if (_endReason == 'none') _buildControls(),
          const SizedBox(height: 28),
        ])),

        // Local PiP
        if (_isVideo && _local != null && _endReason == 'none') _buildLocalPip(),
      ]),
    );
  }

  Widget _buildTopBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    child: Row(children: [
      GestureDetector(onTap: _leave, child: Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withAlpha(20)), child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18))),
      const Spacer(),
      Column(children: [
        Text(widget.isIncoming ? widget.callerName : widget.chatName, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          _connected ? _durationLabel : _connecting ? 'Подключение...' : widget.isIncoming ? (_isVideo ? 'Входящий видеозвонок' : 'Входящий звонок') : 'Звонок...',
          style: TextStyle(color: _connected ? const Color(0xFF4ADE80) : Colors.white.withAlpha(150), fontSize: 13),
        ),
      ]),
      const Spacer(),
      const SizedBox(width: 40),
    ]),
  );

  Widget _buildAvatar(String name, {double size = 110}) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [Color(0xFF6C3EF4), Color(0xFF4B1FD1)]),
      boxShadow: [BoxShadow(color: const Color(0xFF6C3EF4).withAlpha(90), blurRadius: 36, spreadRadius: 8)]),
    child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(color: Colors.white, fontSize: size * 0.4, fontWeight: FontWeight.bold))),
  );

  Widget _buildIncomingRing() => Column(mainAxisSize: MainAxisSize.min, children: [
    ScaleTransition(scale: _pulseAnim, child: _buildAvatar(widget.callerName)),
    const SizedBox(height: 20),
    Text(widget.callerName, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
    const SizedBox(height: 6),
    Text(_isVideo ? 'Входящий видеозвонок' : 'Входящий звонок', style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 15)),
    const SizedBox(height: 44),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _ringBtn(Icons.call_end, const Color(0xFFEF4444), 'Отклонить', _leave),
      const SizedBox(width: 64),
      _ringBtn(Icons.call, const Color(0xFF22C55E), 'Принять', _join),
    ]),
  ]);

  Widget _ringBtn(IconData icon, Color color, String label, VoidCallback onTap) => Column(mainAxisSize: MainAxisSize.min, children: [
    GestureDetector(onTap: onTap, child: Container(width: 68, height: 68, decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: color.withAlpha(100), blurRadius: 20, spreadRadius: 4)]), child: Icon(icon, color: Colors.white, size: 30))),
    const SizedBox(height: 8),
    Text(label, style: TextStyle(color: Colors.white.withAlpha(170), fontSize: 13)),
  ]);

  Widget _buildCallingOverlay() => Column(mainAxisSize: MainAxisSize.min, children: [
    ScaleTransition(scale: _pulseAnim, child: _buildAvatar(widget.chatName)),
    const SizedBox(height: 20),
    Text(widget.chatName, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
    const SizedBox(height: 6),
    Text('Ожидание ответа...', style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 15)),
  ]);

  Widget _buildConnectedInfo() {
    if (_isVideo && _remote != null) return const SizedBox.shrink();
    final name = widget.isIncoming ? widget.callerName : widget.chatName;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _buildAvatar(name, size: 96),
      const SizedBox(height: 16),
      Text(name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF4ADE80))),
        const SizedBox(width: 6),
        Text(_durationLabel, style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 14, fontWeight: FontWeight.w500)),
      ]),
    ]);
  }

  Widget _buildEndedOverlay() {
    final isPeerLeft = _endReason == 'peer-left';
    final name = widget.isIncoming ? widget.callerName : widget.chatName;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withAlpha(20)),
        child: Icon(isPeerLeft ? Icons.phone_disabled : Icons.wifi_off, size: 38, color: isPeerLeft ? Colors.amber : Colors.redAccent)),
      const SizedBox(height: 16),
      Text(isPeerLeft ? '$name вышел(а)' : 'Соединение потеряно', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Text(isPeerLeft ? 'Звонок завершён' : 'Проверьте подключение', style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 14)),
    ]);
  }

  Widget _buildLocalPip() => Positioned(
    top: 100, right: 16,
    child: Container(
      width: 110, height: 160,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withAlpha(60), width: 1.5), boxShadow: [BoxShadow(color: Colors.black.withAlpha(100), blurRadius: 12)]),
      child: ClipRRect(borderRadius: BorderRadius.circular(13), child: RTCVideoView(_localRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover, mirror: true)),
    ),
  );

  Widget _buildControls() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _ctrlBtn(icon: _muted ? Icons.mic_off : Icons.mic, active: _muted, activeColor: const Color(0xFFEF4444), onTap: _toggleMute, label: 'Микрофон'),
      GestureDetector(onTap: _leave, child: Container(width: 68, height: 68, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFEF4444), boxShadow: [BoxShadow(color: Color(0x66EF4444), blurRadius: 20, spreadRadius: 4)]), child: const Icon(Icons.call_end, color: Colors.white, size: 30))),
      if (_isVideo) ...[
        _ctrlBtn(icon: _vidOff ? Icons.videocam_off : Icons.videocam, active: _vidOff, activeColor: const Color(0xFFEF4444), onTap: _toggleVideo, label: 'Камера'),
        _ctrlBtn(icon: Icons.flip_camera_android, active: false, activeColor: const Color(0xFF6C3EF4), onTap: _switchCamera, label: 'Перевернуть'),
      ] else
        _ctrlBtn(icon: Icons.volume_up, active: false, activeColor: const Color(0xFF6C3EF4), onTap: () {}, label: 'Динамик'),
    ]),
  );

  Widget _ctrlBtn({required IconData icon, required bool active, required Color activeColor, required VoidCallback onTap, required String label}) => GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 54, height: 54,
        decoration: BoxDecoration(shape: BoxShape.circle, color: active ? activeColor.withAlpha(40) : Colors.white.withAlpha(25), border: Border.all(color: active ? activeColor.withAlpha(120) : Colors.white.withAlpha(30))),
        child: Icon(icon, color: active ? activeColor : Colors.white, size: 24)),
      const SizedBox(height: 5),
      Text(label, style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 11)),
    ]),
  );
}
