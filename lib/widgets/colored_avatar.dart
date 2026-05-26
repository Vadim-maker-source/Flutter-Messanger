import 'package:flutter/material.dart';

/// Универсальный аватар, повторяющий поведение веб-версии
/// (`components/Avatar.tsx` + `lib/avatar.ts` в Next.js проекте).
///
/// Поведение:
///   • если [imageUrl] начинается с `#` (hex-цвет, сгенерированный
///     `generateAvatarColor()` при создании чата/сервера/канала) —
///     рисуем заливку этим цветом и первую букву [title] контрастным
///     цветом (как в `components/Avatar.tsx`);
///   • если [imageUrl] — обычная http(s)-ссылка — грузим картинку;
///   • иначе — фиолетовый градиентный фолбэк с буквой.
///
/// [borderRadius] по умолчанию — круг (size / 2). Для серверов/каналов
/// можно передать прямоугольный радиус, как в веб-сайдбаре.
class ColoredAvatar extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final double size;
  final BorderRadius? borderRadius;

  const ColoredAvatar({
    super.key,
    required this.imageUrl,
    required this.title,
    this.size = 48,
    this.borderRadius,
  });

  bool get _isHexColor {
    final s = imageUrl;
    if (s == null || s.isEmpty || !s.startsWith('#')) return false;
    if (s.length != 4 && s.length != 7 && s.length != 9) return false;
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(s.substring(1));
  }

  Color _parseHex(String hex) {
    var h = hex.substring(1);
    if (h.length == 3) {
      h = h.split('').map((c) => '$c$c').join();
    }
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  }

  /// Точно как `getContrastColor` в `components/Avatar.tsx`.
  Color _contrastColor(Color c) {
    final lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
    return lum > 0.55 ? const Color(0xCC000000) : const Color(0xEEFFFFFF);
  }

  String get _letter =>
      title.trim().isEmpty ? '?' : title.trim().characters.first.toUpperCase();

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(size);

    if (_isHexColor) {
      final bg = _parseHex(imageUrl!);
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        alignment: Alignment.center,
        child: Text(
          _letter,
          style: TextStyle(
            color: _contrastColor(bg),
            fontWeight: FontWeight.w700,
            fontSize: size * 0.38,
          ),
        ),
      );
    }

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, e, s) => _fallback(radius),
        ),
      );
    }

    return _fallback(radius);
  }

  Widget _fallback(BorderRadius radius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0x336C3EF4), Color(0x33A78BFA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: radius,
      ),
      alignment: Alignment.center,
      child: Text(
        _letter,
        style: TextStyle(
          color: const Color(0xFFA78BFA),
          fontWeight: FontWeight.w700,
          fontSize: size * 0.38,
        ),
      ),
    );
  }
}
