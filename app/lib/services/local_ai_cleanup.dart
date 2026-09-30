import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Borra lo que dejó en el móvil la prueba de IA local con Gemma (guardada en
/// la rama `ia-local-gemma`): el modelo, de 2,5 a 3,5 GB, las cachés del motor
/// y su historial de ejecuciones.
///
/// No hace nada si no hay restos, así que es seguro llamarlo en cada arranque.
/// Se puede quitar cuando ya no quede ningún móvil que instalara esa versión.
Future<void> deleteLocalAiLeftovers() async {
  try {
    for (final dir in [await getApplicationDocumentsDirectory(), await getApplicationSupportDirectory()]) {
      if (!await dir.exists()) continue;
      final aBorrar = <File>[];
      await for (final entidad in dir.list(recursive: true, followLinks: false)) {
        if (entidad is! File) continue;
        final nombre = entidad.uri.pathSegments.last.toLowerCase();
        if (nombre.contains('.litertlm') || nombre.startsWith('gemma-4-') || nombre == 'ia_local.json') {
          aBorrar.add(entidad);
        }
      }
      for (final fichero in aBorrar) {
        try {
          await fichero.delete();
        } catch (_) {}
      }
    }
  } catch (_) {
    // Limpieza de cortesía: si falla, la app sigue igual.
  }
}
