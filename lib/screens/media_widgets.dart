import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import 'package:gal/gal.dart';

const _purple = Color(0xFF7166D8);
const _bubbleBg = Color(0x1AFFFFFF);

/// Скачивает файл по URL в директорию Downloads / временную папку и открывает.
/// Возвращает `true` при успехе.
Future<bool> downloadAndOpen(String url, {String? fileName}) async {
  try {
    final dir = await _downloadDir();
    final name = fileName ?? url.split('/').last.split('?').first;
    final savePath = '${dir.path}/$name';

    // Если файл уже существует — просто открываем
    final existing = File(savePath);
    if (await existing.exists()) {
      await OpenFilex.open(savePath);
      return true;
    }

    await Dio().download(url, savePath);
    await OpenFilex.open(savePath);
    return true;
  } catch (_) {
    return false;
  }
}

/// Сохраняет фото/видео в галерею устройства.
Future<bool> saveToGallery(String url, {required bool isVideo}) async {
  try {
    final dir = await getTemporaryDirectory();
    final ext = isVideo ? 'mp4' : 'jpg';
    final name = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final savePath = '${dir.path}/$name';
    await Dio().download(url, savePath);
    if (isVideo) {
      await Gal.putVideo(savePath);
    } else {
      await Gal.putImage(savePath);
    }
    return true;
  } catch (_) {
    return false;
  }
}

Future<Directory> _downloadDir() async {
  // На Android — папка Downloads, на iOS — временная директория приложения
  if (Platform.isAndroid) {
    return Directory('/storage/emulated/0/Download');
  }
  return getApplicationDocumentsDirectory();
}

/// Показывает снек-бар с результатом скачивания.
void showDownloadSnack(BuildContext context, bool ok) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(ok ? 'Файл сохранён' : 'Не удалось сохранить файл'),
      duration: const Duration(seconds: 2),
    ),
  );
}

// ─── Фото ────────────────────────────────────────────────────────────────────

class ImageMessage extends StatelessWidget {
  final String url;
  const ImageMessage({super.key, required this.url});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => Navigator.push(context, MaterialPageRoute(
      builder: (_) => _FullScreenImage(url: url),
    )),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280, maxHeight: 280, minWidth: 180),
      child: Image.network(url,
          width: double.infinity,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, p) => p == null ? child
              : Container(width: 220, height: 160,
                  color: const Color(0xFF1D2633),
                  child: const Center(child: CircularProgressIndicator(color: _purple, strokeWidth: 2)))),
    ),
  );
}

class _FullScreenImage extends StatelessWidget {
  final String url;
  const _FullScreenImage({required this.url});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0,
      leading: IconButton(icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context)),
      actions: [
        IconButton(
          icon: const Icon(Icons.save_alt_rounded, color: Colors.white),
          tooltip: 'Сохранить в галерею',
          onPressed: () async {
            final ok = await saveToGallery(url, isVideo: false);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok ? 'Сохранено в галерею' : 'Не удалось сохранить'),
                duration: const Duration(seconds: 2),
              ));
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.download_rounded, color: Colors.white),
          tooltip: 'Скачать',
          onPressed: () async {
            final ok = await downloadAndOpen(url,
                fileName: url.split('/').last.split('?').first);
            if (context.mounted) showDownloadSnack(context, ok);
          },
        ),
      ],
    ),
    body: Center(child: InteractiveViewer(
      minScale: 0.5, maxScale: 4.0,
      child: Image.network(url, fit: BoxFit.contain),
    )),
  );
}

// ─── Видео (с полноэкранным режимом) ─────────────────────────────────────────

class VideoMessage extends StatefulWidget {
  final String url;
  const VideoMessage({super.key, required this.url});
  @override
  State<VideoMessage> createState() => _VideoMessageState();
}

class _VideoMessageState extends State<VideoMessage> {
  late VideoPlayerController _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) { if (mounted) setState(() => _ready = true); });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _openFullscreen() {
    _ctrl.pause();
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _FullScreenVideo(url: widget.url),
    ));
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: _openFullscreen,
    child: SizedBox(width: 280, height: 180,
      child: Stack(fit: StackFit.expand, children: [
        _ready
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: VideoPlayer(_ctrl))
            : Container(color: const Color(0xFF1D2633),
                child: const Center(child: CircularProgressIndicator(color: _purple, strokeWidth: 2))),
        // Play button overlay
        Center(child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
          ),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
        )),
        // Fullscreen hint
        Positioned(bottom: 8, right: 8,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 18),
          ),
        ),
      ]),
    ),
  );
}

/// Полноэкранный видеоплеер с controls и скачиванием.
class _FullScreenVideo extends StatefulWidget {
  final String url;
  const _FullScreenVideo({required this.url});
  @override
  State<_FullScreenVideo> createState() => _FullScreenVideoState();
}

class _FullScreenVideoState extends State<_FullScreenVideo> {
  late VideoPlayerController _ctrl;
  bool _ready = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) { setState(() => _ready = true); _ctrl.play(); }
      });
    _ctrl.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      child: Stack(children: [
        Center(child: _ready
            ? AspectRatio(aspectRatio: _ctrl.value.aspectRatio, child: VideoPlayer(_ctrl))
            : const CircularProgressIndicator(color: _purple)),
        if (_showControls) ...[
          // Top bar — back + download
          Positioned(top: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 40, 8, 8),
              decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
              )),
              child: Row(children: [
                IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.save_alt_rounded, color: Colors.white),
                  tooltip: 'Сохранить в галерею',
                  onPressed: () async {
                    final ok = await saveToGallery(widget.url, isVideo: true);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok ? 'Сохранено в галерею' : 'Не удалось сохранить'),
                        duration: const Duration(seconds: 2),
                      ));
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.download_rounded, color: Colors.white),
                  tooltip: 'Скачать',
                  onPressed: () async {
                    final ok = await downloadAndOpen(widget.url,
                        fileName: 'video_${DateTime.now().millisecondsSinceEpoch}.mp4');
                    if (context.mounted) showDownloadSnack(context, ok);
                  },
                ),
              ]),
            ),
          ),
          // Bottom controls
          Positioned(bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
              )),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Progress bar
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: _purple,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: _purple,
                  ),
                  child: Slider(
                    value: _ctrl.value.duration.inMilliseconds > 0
                        ? (_ctrl.value.position.inMilliseconds / _ctrl.value.duration.inMilliseconds).clamp(0.0, 1.0)
                        : 0.0,
                    onChanged: (v) => _ctrl.seekTo(Duration(
                        milliseconds: (v * _ctrl.value.duration.inMilliseconds).round())),
                  ),
                ),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(_fmt(_ctrl.value.position),
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  Row(children: [
                    IconButton(
                      icon: Icon(_ctrl.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white, size: 32),
                      onPressed: () => _ctrl.value.isPlaying ? _ctrl.pause() : _ctrl.play(),
                    ),
                  ]),
                  Text(_fmt(_ctrl.value.duration),
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ]),
            ),
          ),
        ],
      ]),
    ),
  );
}

// ─── Видеокружок ─────────────────────────────────────────────────────────────

class RoundVideoMessage extends StatefulWidget {
  final String url;
  const RoundVideoMessage({super.key, required this.url});
  @override
  State<RoundVideoMessage> createState() => _RoundVideoMessageState();
}

class _RoundVideoMessageState extends State<RoundVideoMessage> {
  late VideoPlayerController _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) { if (mounted) setState(() => _ready = true); });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { _ctrl.value.isPlaying ? _ctrl.pause() : _ctrl.play(); setState(() {}); },
    onLongPress: () async {
      final ok = await downloadAndOpen(widget.url,
          fileName: 'video_${DateTime.now().millisecondsSinceEpoch}.mp4');
      if (context.mounted) showDownloadSnack(context, ok);
    },
    child: SizedBox(width: 160, height: 160,
      child: Stack(alignment: Alignment.center, children: [
        ClipOval(child: SizedBox(width: 160, height: 160,
          child: _ready ? VideoPlayer(_ctrl)
              : Container(color: const Color(0xFF1D2633)))),
        Container(width: 48, height: 48,
          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
          child: Icon(_ctrl.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white, size: 30)),
      ]),
    ),
  );
}

// ─── Аудио ───────────────────────────────────────────────────────────────────

class AudioMessage extends StatefulWidget {
  final String url;
  final bool isMe;
  final List<double>? waveform;
  const AudioMessage({super.key, required this.url, this.isMe = false, this.waveform});
  @override
  State<AudioMessage> createState() => _AudioMessageState();
}

class _AudioMessageState extends State<AudioMessage> {
  final _player = AudioPlayer();
  bool _playing = false;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  late List<double> _bars;

  @override
  void initState() {
    super.initState();
    _bars = widget.waveform ?? _generateWaveform(widget.url);
    _player.setUrl(widget.url).then((_) {
      if (mounted) setState(() => _dur = _player.duration ?? Duration.zero);
    });
    _player.positionStream.listen((p) { if (mounted) setState(() => _pos = p); });
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _player.stop();
        _player.seek(Duration.zero);
        if (mounted) setState(() => _playing = false);
      } else {
        if (mounted) setState(() => _playing = s.playing);
      }
    });
  }

  /// Генерирует псевдо-waveform из хеша URL (стабильный для одного и того же файла).
  static List<double> _generateWaveform(String url) {
    final seed = url.hashCode;
    const count = 40;
    return List.generate(count, (i) {
      // Простой PRNG на основе seed + index
      final v = ((seed * 31 + i * 17) ^ (i * 1234567)) & 0x7FFFFFFF;
      return 0.2 + 0.8 * ((v % 100) / 100.0);
    });
  }

  @override
  void dispose() { _player.dispose(); super.dispose(); }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final progress = _dur.inMilliseconds > 0
        ? (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0) : 0.0;

    return SizedBox(width: 260,
      child: Row(children: [
        GestureDetector(
          onTap: () => _playing ? _player.pause() : _player.play(),
          child: Container(width: 40, height: 40,
            decoration: const BoxDecoration(color: _purple, shape: BoxShape.circle),
            child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white, size: 22)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTapDown: (details) {
              if (_dur.inMilliseconds <= 0) return;
              final box = context.findRenderObject() as RenderBox;
              // Учитываем отступ кнопки play (40+10=50)
              final localX = details.localPosition.dx;
              final width = box.size.width - 50 - 30; // минус кнопка download
              final ratio = (localX / width).clamp(0.0, 1.0);
              _player.seek(Duration(milliseconds: (ratio * _dur.inMilliseconds).round()));
            },
            child: CustomPaint(
              size: const Size(double.infinity, 28),
              painter: _WaveformPainter(
                bars: _bars,
                progress: progress,
                activeColor: widget.isMe ? Colors.white : _purple,
                inactiveColor: widget.isMe
                    ? Colors.white.withValues(alpha: 0.3)
                    : _purple.withValues(alpha: 0.3),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(_playing ? _fmt(_pos) : _fmt(_dur),
              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
        ])),
        // Download button
        IconButton(
          icon: Icon(Icons.download_rounded,
              color: Colors.white.withValues(alpha: 0.5), size: 20),
          onPressed: () async {
            final ok = await downloadAndOpen(widget.url,
                fileName: 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a');
            if (context.mounted) showDownloadSnack(context, ok);
          },
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }
}

// ─── Waveform Painter ────────────────────────────────────────────────────────

class _WaveformPainter extends CustomPainter {
  final List<double> bars;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final count = bars.length;
    final barWidth = size.width / count * 0.6;
    final gap = size.width / count * 0.4;
    final step = barWidth + gap;
    final maxH = size.height;

    for (int i = 0; i < count; i++) {
      final x = i * step;
      final h = (bars[i] * maxH).clamp(3.0, maxH);
      final y = (maxH - h) / 2;
      final isActive = (i / count) <= progress;
      final paint = Paint()
        ..color = isActive ? activeColor : inactiveColor
        ..strokeCap = StrokeCap.round;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, h),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress || old.activeColor != activeColor;
}

// ─── Файл (с реальным скачиванием) ───────────────────────────────────────────

class FileMessage extends StatelessWidget {
  final String url;
  final String? fileName;
  final bool isMe;
  const FileMessage({super.key, required this.url, this.fileName, this.isMe = false});

  @override
  Widget build(BuildContext context) {
    final name = fileName ?? url.split('/').last.split('?').first;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';

    return GestureDetector(
      onTap: () async {
        final ok = await downloadAndOpen(url, fileName: name);
        if (context.mounted) showDownloadSnack(context, ok);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF7166D8).withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: _purple.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Text(_icon(ext), style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 2),
            Text('Скачать файл',
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
          ])),
          const SizedBox(width: 8),
          Icon(Icons.download_rounded, size: 22, color: Colors.white.withValues(alpha: 0.7)),
        ]),
      ),
    );
  }

  String _icon(String ext) {
    switch (ext) {
      case 'pdf': return '📕';
      case 'doc': case 'docx': return '📘';
      case 'xls': case 'xlsx': return '📗';
      case 'ppt': case 'pptx': return '📙';
      case 'zip': case 'rar': case '7z': return '🗜️';
      case 'txt': return '📄';
      default: return '📎';
    }
  }
}
