import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_app/services/update_checker.dart';

void main() {
  group('esVersionMayor', () {
    test('detecta una versión posterior', () {
      expect(esVersionMayor('1.0.1', '1.0.0'), isTrue);
      expect(esVersionMayor('1.1.0', '1.0.9'), isTrue);
      expect(esVersionMayor('2.0.0', '1.9.9'), isTrue);
    });

    test('no avisa si es la misma o anterior', () {
      expect(esVersionMayor('1.0.0', '1.0.0'), isFalse);
      expect(esVersionMayor('1.0.0', '1.0.1'), isFalse);
      expect(esVersionMayor('1.9.9', '2.0.0'), isFalse);
    });

    test('compara por número, no como texto', () {
      // El fallo clásico: "1.10.0" va antes que "1.9.0" alfabéticamente, pero
      // es posterior. Comparar como cadenas dejaría de avisar en la décima
      // versión menor y nadie se enteraría.
      expect(esVersionMayor('1.10.0', '1.9.0'), isTrue);
      expect(esVersionMayor('1.9.0', '1.10.0'), isFalse);
    });

    test('admite el prefijo v de los tags de git', () {
      expect(esVersionMayor('v1.2.0', '1.1.0'), isTrue);
      expect(esVersionMayor('V1.0.0', '1.0.0'), isFalse);
    });

    test('trata las partes que faltan como cero', () {
      expect(esVersionMayor('1.1', '1.1.0'), isFalse);
      expect(esVersionMayor('1.1.1', '1.1'), isTrue);
    });

    test('ignora sufijos de pre-release y de build', () {
      expect(esVersionMayor('1.2.0-beta', '1.1.0'), isTrue);
      expect(esVersionMayor('1.0.0+5', '1.0.0'), isFalse);
    });

    test('no revienta con basura', () {
      expect(esVersionMayor('', '1.0.0'), isFalse);
      expect(esVersionMayor('release', '1.0.0'), isFalse);
    });
  });

  group('apkParaInstalar', () {
    test('prefiere la de arm64 cuando el release viene partido por ABI', () {
      final url = apkParaInstalar([
        (nombre: 'app-armeabi-v7a-release.apk', url: 'https://x/v7a.apk'),
        (nombre: 'app-arm64-v8a-release.apk', url: 'https://x/arm64.apk'),
        (nombre: 'app-x86_64-release.apk', url: 'https://x/x86.apk'),
      ]);
      expect(url, 'https://x/arm64.apk');
    });

    test('usa la única que haya si no está partido', () {
      final url = apkParaInstalar([(nombre: 'app-release.apk', url: 'https://x/app.apk')]);
      expect(url, 'https://x/app.apk');
    });

    test('ignora los ficheros que no son APK', () {
      final url = apkParaInstalar([
        (nombre: 'notas.txt', url: 'https://x/notas.txt'),
        (nombre: 'app-release.apk', url: 'https://x/app.apk'),
      ]);
      expect(url, 'https://x/app.apk');
    });

    test('devuelve null si el release no trae ningún APK', () {
      expect(apkParaInstalar([(nombre: 'notas.txt', url: 'https://x/notas.txt')]), isNull);
      expect(apkParaInstalar([]), isNull);
    });
  });
}
