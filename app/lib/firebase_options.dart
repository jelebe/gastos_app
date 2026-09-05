// Generado a mano a partir de la app Android registrada en el proyecto
// Firebase "gastoscanos" (sin flutterfire_cli, por problemas de auth con la
// CLI de firebase en esta máquina). Si se añade iOS/web más adelante, hay
// que registrar esa plataforma en Firebase y añadir su caso aquí.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions no tiene configuración para web todavía.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions solo tiene configuración para Android por ahora.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBl1Frr79gvG4p35CGA9QucBgf2ExMBqd8',
    appId: '1:158852635987:android:8b12a07d80e375296dd5a6',
    messagingSenderId: '158852635987',
    projectId: 'gastoscanos',
    storageBucket: 'gastoscanos.firebasestorage.app',
  );
}
