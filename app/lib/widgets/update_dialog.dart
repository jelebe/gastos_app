import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../services/update_checker.dart';

/// Avisa de que hay una versión nueva publicada en GitHub, si la hay, y la
/// instala: se descarga el APK dentro de la app y se le pasa al instalador de
/// Android, que la pone encima de la actual sin perder los datos.
///
/// Se llama al abrir la app y no molesta si algo falla: sin red, o si ya se
/// está en la última, no se ve nada.
Future<void> maybeShowUpdateDialog(BuildContext context) async {
  final update = await buscarActualizacion();
  if (update == null || !context.mounted) return;

  final actualizar = await showDialog<bool>(
    context: context,
    // Como en el resto de mis apps: hay que decir que sí o que más tarde, no
    // se cierra tocando fuera.
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Nueva actualización disponible'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hay una nueva versión (${update.version}) disponible. ¿Quieres actualizar ahora?'),
            if (update.notas.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(update.notas, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Más tarde')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Actualizar')),
      ],
    ),
  );
  if (actualizar != true || !context.mounted) return;

  await _descargarEInstalar(context, update);
}

Future<void> _descargarEInstalar(BuildContext context, AppUpdate update) async {
  final progreso = ValueNotifier<double?>(0);
  var cancelado = false;

  // El diálogo de progreso se cierra solo al acabar la descarga. Se guarda el
  // navigator antes de esperar: al volver del `await`, el context del diálogo
  // ya no sirve para cerrarlo.
  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Descargando actualización'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progreso,
          builder: (context, valor, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: valor),
              const SizedBox(height: 12),
              Text(valor == null ? 'Descargando…' : '${(valor * 100).toStringAsFixed(0)} %'),
            ],
          ),
        ),
      ),
    ),
  );

  final ruta = await descargarApk(
    update,
    onProgress: (valor) {
      if (!cancelado) progreso.value = valor;
    },
  );
  cancelado = true;
  progreso.dispose();
  navigator.pop(); // cierra el diálogo de progreso

  if (!context.mounted) return;
  if (ruta == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se ha podido descargar la actualización.')),
    );
    return;
  }

  // Abrir el APK lanza el instalador del sistema. La primera vez Android pide
  // permiso para instalar desde esta app; si se deniega, no pasa nada más.
  final resultado = await OpenFilex.open(ruta, type: 'application/vnd.android.package-archive');
  if (resultado.type != ResultType.done && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No se ha podido abrir el instalador: ${resultado.message}')),
    );
  }
}
