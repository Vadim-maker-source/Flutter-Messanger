import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../main.dart';

// ─── Запись голосового сообщения ─────────────────────────────────────────────

class VoiceRecorderSheet extends StatefulWidget {
  final void Function(File file) onDone;
  const VoiceRecorderSheet({super.key, required this.onDone});

  @override
  State<VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<VoiceRecorderSheet> {
  final _recorder = AudioRecorder();
  bool _recording = false;
  int _seconds = 0;
  Timer? _timer;
  String? _path;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final dir = await getTemporaryDirectory();
    _path = p.join(dir.path, 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: _path!);
    setState(() => _recording = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _seconds++);
    });
  }

  Future<void> _stop({bool send = true}) async {
    _timer?.cancel();
    await _recorder.stop();
    setState(() => _recording = false);
    if (send && _path != null) {
      widget.onDone(File(_path!));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  String get _time {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          // Анимированный индикатор
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic_rounded, size: 36, color: Colors.red),
          ),
          const SizedBox(height: 16),
          Text(_time,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Запись...', style: TextStyle(color: AppColors.muted, fontSize: 14)),
          const SizedBox(height: 32),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            // Отмена
            GestureDetector(
              onTap: () => _stop(send: false),
              child: Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline_rounded, color: AppColors.muted),
              ),
            ),
            // Отправить
            GestureDetector(
              onTap: () => _stop(send: true),
              child: Container(
                width: 72, height: 72,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.darkAccent],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 28),
              ),
            ),
          ]),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

// ─── Запись видеокружка ───────────────────────────────────────────────────────

class VideoNoteRecorder extends StatefulWidget {
  final void Function(File file) onDone;
  const VideoNoteRecorder({super.key, required this.onDone});

  @override
  State<VideoNoteRecorder> createState() => _VideoNoteRecorderState();
}

class _VideoNoteRecorderState extends State<VideoNoteRecorder> {
  CameraController? _cam;
  bool _recording = false;
  bool _ready = false;
  int _seconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) { Navigator.pop(context); return; }
    // Предпочитаем фронтальную
    final cam = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _cam = CameraController(cam, ResolutionPreset.medium, enableAudio: true);
    await _cam!.initialize();
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _startRecording() async {
    await _cam!.startVideoRecording();
    setState(() { _recording = true; _seconds = 0; });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _seconds++);
      if (_seconds >= 60) _stopRecording(); // макс 60 сек
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final xfile = await _cam!.stopVideoRecording();
    setState(() => _recording = false);
    widget.onDone(File(xfile.path));
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cam?.dispose();
    super.dispose();
  }

  String get _time {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          // Превью камеры в круге
          Center(
            child: ClipOval(
              child: SizedBox(
                width: 280, height: 280,
                child: _ready
                    ? CameraPreview(_cam!)
                    : const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              ),
            ),
          ),

          // Прогресс-кольцо
          if (_recording)
            Center(child: SizedBox(
              width: 296, height: 296,
              child: CircularProgressIndicator(
                value: _seconds / 60,
                strokeWidth: 4,
                color: Colors.red,
                backgroundColor: Colors.white24,
              ),
            )),

          // Таймер
          if (_recording)
            Positioned(
              top: 20, left: 0, right: 0,
              child: Center(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_time,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              )),
            ),

          // Кнопки
          Positioned(
            bottom: 40, left: 0, right: 0,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              // Отмена
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white24, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white),
                ),
              ),
              // Запись / Стоп
              GestureDetector(
                onTap: _ready ? (_recording ? _stopRecording : _startRecording) : null,
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: _recording ? Colors.red : Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _recording ? Icons.stop_rounded : Icons.videocam_rounded,
                    color: _recording ? Colors.white : Colors.black,
                    size: 36,
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
