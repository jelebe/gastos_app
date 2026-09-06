import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Repositorio del que se sacan las actualizaciones. Es público, así que la
/// API de releases responde sin token: no hay que meter credenciales en la
/// app para esto.
const _repo = 'jelebe/gastos_app';

/// Una versión publicada en GitHub que es más nueva que la instalada.
class AppUpdate {
  AppUpdate({required this.version, required this.apkUrl, required this.notas});

  final String version;

  /// Enlace directo al APK del release: se descarga dentro de la app y se le
  /// pasa al instalador de Android, que lo pone encima de la versión actual.
  final String apkUrl;
  final String notas;
}

/// Compara dos versiones tipo "1.4.2" y dice si [remota] es posterior a
/// [local]. Se comparan los números parte a parte (no como texto: "1.10.0" es
/// posterior a "1.9.0", aunque alfabéticamente vaya antes), y las partes que
/// falten cuentan como 0, de modo que "1.1" y "1.1.0" son la misma.
bool esVersionMayor(String remota, String local) {
  List<int> partes(String v) {
    // Se admite el prefijo "v" de los tags y se corta cualquier sufijo tipo
    // "-beta", que aquí no distingue nada.
    final limpio = v.trim().replaceFirst(RegExp(r'^v', caseSensitive: false), '').split(RegExp(r'[-+]')).first;
    return [for (final p in limpio.split('.')) int.tryParse(p) ?? 0];
  }

  final a = partes(remota);
  final b = partes(local);
  for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
    final numeroA = i < a.length ? a[i] : 0;
    final numeroB = i < b.length ? b[i] : 0;
    if (numeroA != numeroB) return numeroA > numeroB;
  }
  return false;
}

/// Elige el APK que hay que ofrecer entre los ficheros de un release.
///
/// Si el release trae las APK partidas por arquitectura, la buena es la de
/// arm64: es la de cualquier móvil actual. Si solo hay una (la universal),
/// esa vale para todos.
String? apkParaInstalar(List<({String nombre, String url})> assets) {
  final apks = assets.where((a) => a.nombre.toLowerCase().endsWith('.apk')).toList();
  if (apks.isEmpty) return null;
  for (final apk in apks) {
    if (apk.nombre.toLowerCase().contains('arm64')) return apk.url;
  }
  return apks.first.url;
}

/// Mira si hay una versión más nueva publicada en GitHub.
///
/// Devuelve `null` si ya se está en la última, si el repositorio no tiene
/// releases o si algo falla (sin red, la API a tope de peticiones...): esto
/// es una comodidad, no puede impedir usar la app ni dar un error en la cara.
Future<AppUpdate?> buscarActualizacion({Duration timeout = const Duration(seconds: 6)}) async {
  try {
    final info = await PackageInfo.fromPlatform();
    final respuesta = await http
        .get(
          Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(timeout);
    if (respuesta.statusCode != 200) return null;

    final datos = jsonDecode(respuesta.body) as Map<String, dynamic>;
    final tag = datos['tag_name'] as String?;
    if (tag == null || !esVersionMayor(tag, info.version)) return null;

    final assets = [
      for (final a in (datos['assets'] as List? ?? []))
        (nombre: (a as Map)['name'] as String? ?? '', url: a['browser_download_url'] as String? ?? ''),
    ];
    final apkUrl = apkParaInstalar(assets);
    if (apkUrl == null || apkUrl.isEmpty) return null;

    return AppUpdate(
      version: tag.replaceFirst(RegExp(r'^v', caseSensitive: false), ''),
      apkUrl: apkUrl,
      notas: (datos['body'] as String? ?? '').trim(),
    );
  } catch (_) {
    return null;
  }
}

/// Descarga el APK de [update] a la caché de la app y devuelve su ruta.
///
/// Va informando del avance por [onProgress] (de 0 a 1, o `null` mientras el
/// servidor no diga cuánto pesa): son más de 30 MB, así que sin señal de vida
/// parece que se ha colgado. Devuelve `null` si la descarga falla.
Future<String?> descargarApk(
  AppUpdate update, {
  void Function(double? progreso)? onProgress,
}) async {
  try {
    final cliente = http.Client();
    final respuesta = await cliente.send(http.Request('GET', Uri.parse(update.apkUrl)));
    if (respuesta.statusCode != 200) return null;

    final dir = await getTemporaryDirectory();
    // Nombre fijo: así una descarga a medias de un intento anterior se
    // sobrescribe en vez de ir dejando APKs sueltos en la caché.
    final fichero = File('${dir.path}/canogasto-update.apk');
    final salida = fichero.openWrite();
    final total = respuesta.contentLength;
    var descargado = 0;

    await for (final trozo in respuesta.stream) {
      salida.add(trozo);
      descargado += trozo.length;
      onProgress?.call(total == null || total == 0 ? null : descargado / total);
    }
    await salida.close();
    cliente.close();
    return fichero.path;
  } catch (_) {
    return null;
  }
}
