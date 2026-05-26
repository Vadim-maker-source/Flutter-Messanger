import 'dart:io';
import 'package:flutter/material.dart';

import 'chat_picker_screen.dart';

/// Обёртка для совместимости со старым API. Внутри использует
/// [ChatPickerScreen] в режиме шеринга — единый код для пересылки и шеринга.
class ShareChatPicker extends StatelessWidget {
  final String? sharedText;
  final List<File>? sharedFiles;

  const ShareChatPicker({super.key, this.sharedText, this.sharedFiles});

  @override
  Widget build(BuildContext context) {
    return ChatPickerScreen(
      sharedText: sharedText,
      sharedFiles: sharedFiles,
    );
  }
}
