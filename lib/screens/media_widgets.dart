import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

const _purple = Color(0xFF7166D8);
const _bubbleBg = Color(0x1AFFFFFF); // white/10

// ─── Фото ────────────────────────────────────────────────────────────────────

class ImageMessage extends StatelessWidget {
  final String url;
  const ImageMessage({super.key, required this.url});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(children: [
          InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
          Positioned(top: 8, right: 8,
            child: IconButton(icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context))),
        ]),
      ),
    ),
    child: ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(14), topRight: Radius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280, maxHeight: 280, minWidth: 180),
        child: Image.network(url,
            width: double.infinity,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, p) => p == null ? child
                : Container(width: 220, height: 160,
                    color: const Color(0xFF18181B),
                    child: const Center(child: CircularProgressIndicator(color: _purple, strokeWidth: 2)))),
      ),
    ),
  );
}

// ─── Видео ───────────────────────────────────────────────────────────────────

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

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { _ctrl.value.isPlaying ? _ctrl.pause() : _ctrl.play(); setState(() {}); },
    child: ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(14), topRight: Radius.circular(14)),
      child: SizedBox(width: 240, height: 160,
        child: Stack(fit: StackFit.expand, children: [
          _ready ? VideoPlayer(_ctrl)
              : Container(color: const Color(0xFF18181B),
                  child: const Center(child: CircularProgressIndicator(color: _purple, strokeWidth: 2))),
          Center(child: Container(
            width: 48, height: 48,
            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
            child: Icon(_ctrl.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white, size: 30),
          )),
        ]),
      ),
    ),
  );
}

// ─── Видеокружок (w-40 h-40 rounded-full) ────────────────────────────────────

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
    child: SizedBox(width: 160, height: 160,
      child: Stack(alignment: Alignment.center, children: [
        ClipOval(child: SizedBox(width: 160, height: 160,
          child: _ready ? VideoPlayer(_ctrl)
              : Container(color: const Color(0xFF18181B)))),
        Container(width: 48, height: 48,
          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
          child: Icon(_ctrl.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white, size: 30)),
      ]),
    ),
  );
}

// ─── Аудио (bg-white/10 rounded-xl p-3 min-w-[260px]) ────────────────────────

class AudioMessage extends StatefulWidget {
  final String url;
  final bool isMe;
  const AudioMessage({super.key, required this.url, this.isMe = false});
  @override
  State<AudioMessage> createState() => _AudioMessageState();
}

class _AudioMessageState extends State<AudioMessage> {
  final _player = AudioPlayer();
  bool _playing = false;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.setUrl(widget.url).then((_) {
      if (mounted) setState(() => _dur = _player.duration ?? Duration.zero);
    });
    _player.positionStream.listen((p) { if (mounted) setState(() => _pos = p); });
    _player.playerStateStream.listen((s) {
      if (mounted) setState(() => _playing = s.playing);
      if (s.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        if (mounted) setState(() => _playing = false);
      }
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
        // Кнопка: bg-violet-600
        GestureDetector(
          onTap: () => _playing ? _player.pause() : _player.play(),
          child: Container(width: 40, height: 40,
            decoration: const BoxDecoration(color: _purple, shape: BoxShape.circle),
            child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white, size: 22)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 40 баров (упрощённо — слайдер)
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: _purple,
              inactiveTrackColor: _bubbleBg,
              thumbColor: _purple,
            ),
            child: Slider(
              value: progress,
              onChanged: (v) => _player.seek(
                  Duration(milliseconds: (v * _dur.inMilliseconds).round())),
            ),
          ),
          Text(_fmt(_pos),
              style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4))),
        ])),
      ]),
    );
  }
}

// ─── Файл ────────────────────────────────────────────────────────────────────

class FileMessage extends StatelessWidget {
  final String url;
  final String? fileName;
  final bool isMe;
  const FileMessage({super.key, required this.url, this.fileName, this.isMe = false});

  String _emoji(String name) {
    final ext = name.split('.').last.toLowerCase();
    const map = {
      'pdf': '📄', 'doc': '📝', 'docx': '📝', 'xls': '📊', 'xlsx': '📊',
      'zip': '🗜️', 'rar': '🗜️', 'mp3': '🎵', 'mp4': '🎬',
      'png': '🖼️', 'jpg': '🖼️', 'jpeg': '🖼️',
    };
    return map[ext] ?? '📎';
  }

  @override
  Widget build(BuildContext context) {
    final name = fileName ?? url.split('/').last;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(_emoji(name), style: const TextStyle(fontSize: 28)),
      const SizedBox(width: 10),
      Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
        Text(name.contains('.') ? name.split('.').last.toUpperCase() : 'FILE',
            style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4))),
      ])),
    ]);
  }
}
