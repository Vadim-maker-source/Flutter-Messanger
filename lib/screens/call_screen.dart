import 'package:flutter/material.dart';
import 'package:stream_video_flutter/stream_video_flutter.dart';

class CallScreen extends StatefulWidget {
  final String callId;
  final String callType;
  final bool isIncoming;
  final String callerName;
  final String chatName;

  const CallScreen({
    super.key,
    required this.callId,
    required this.callType,
    required this.isIncoming,
    required this.callerName,
    required this.chatName,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Call? _call;
  bool _isJoining = false;
  bool _joined = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _call = StreamVideo.instance.makeCall(
      callType: StreamCallType.defaultType(),
      id: widget.callId,
    );
  }

  Future<void> _join() async {
    if (_isJoining || _call == null) return;
    setState(() { _isJoining = true; _error = null; });
    try {
      final result = await _call!.join();
      if (result.isSuccess) {
        setState(() { _joined = true; });
      } else {
        setState(() { _error = 'Не удалось подключиться'; });
      }
    } catch (e) {
      setState(() { _error = 'Не удалось подключиться'; });
    } finally {
      if (mounted) setState(() { _isJoining = false; });
    }
  }

  Future<void> _leave() async {
    await _call?.leave();
    if (mounted) Navigator.of(context).pop('ended');
  }

  @override
  void dispose() {
    if (!_joined) _call?.leave();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0E),
      body: _joined && _call != null ? _buildActiveCall() : _buildPreJoin(),
    );
  }

  Widget _buildPreJoin() {
    final isVideo = widget.callType == 'video';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isVideo
                    ? const Color(0xFF3B82F6).withAlpha(50)
                    : const Color(0xFF22C55E).withAlpha(50),
              ),
              child: Icon(
                isVideo ? Icons.videocam : Icons.phone,
                size: 36,
                color: isVideo ? const Color(0xFF60A5FA) : const Color(0xFF4ADE80),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.isIncoming
                  ? 'Входящий ${isVideo ? 'видеозвонок' : 'аудиозвонок'}'
                  : 'Исходящий ${isVideo ? 'видеозвонок' : 'аудиозвонок'}',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.isIncoming ? widget.callerName : widget.chatName,
              style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 16),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withAlpha(75)),
                ),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 14)),
              ),
            ],
            const SizedBox(height: 40),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isJoining ? null : _join,
                    icon: _isJoining
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.phone),
                    label: Text(_isJoining ? 'Подключение...' : (widget.isIncoming ? 'Принять' : 'Начать')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.isIncoming ? const Color(0xFF22C55E) : const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _leave,
                    icon: const Icon(Icons.phone_disabled),
                    label: Text(widget.isIncoming ? 'Отклонить' : 'Отмена'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withAlpha(50),
                      foregroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveCall() {
    return StreamCallContainer(
      call: _call!,
      onLeaveCallTap: _leave,
      onBackPressed: _leave,
    );
  }
}
