// Generated manually from android/app/google-services.json.
// Если позже добавите iOS — пропишите ios FirebaseOptions из GoogleService-Info.plist
// (или запустите `flutterfire configure` чтобы сгенерировать заново).

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions: web не настроен. '
        'Запустите `flutterfire configure` чтобы добавить web-конфиг.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'DefaultFirebaseOptions: $defaultTargetPlatform не настроен. '
          'Сейчас поддерживается только Android. Добавьте конфиг для платформы '
          'через `flutterfire configure`.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDNdVr2TZelCksYWZhrRBfn9tSVP1G1uDc',
    appId: '1:1078556764659:android:318297018d2a41e7a34a86',
    messagingSenderId: '1078556764659',
    projectId: 'messanger-2-f7645',
    storageBucket: 'messanger-2-f7645.firebasestorage.app',
  );
}
