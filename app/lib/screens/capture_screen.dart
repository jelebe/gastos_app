import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../models/ticket_line_item.dart';
import '../services/household_repository.dart';
import '../utils/product_classifier.dart';
import '../utils/ticket_parser.dart';
import 'confirm_ticket_screen.dart';

/// Pantalla de captura: hace la foto, lee el texto en el propio dispositivo
/// con ML Kit y borra la imagen de inmediato. Solo el texto extraído sigue
/// adelante hacia la pantalla de confirmación.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, required this.repository});

  final HouseholdRepository repository;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _captureAndProcess());
  }

  Future<void> _captureAndProcess() async {
    setState(() => _error = null);

    String? imagePath;
    try {
      final photo = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
      if (photo == null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      imagePath = photo.path;

      // Categorías y lo aprendido se piden ya, mientras se lee la foto.
      final datos = (widget.repository.loadCategories(), widget.repository.loadLearnedLines()).wait;
      // Si fallan antes de llegar a esperarlos, que no quede como error suelto:
      // ya se recoge abajo, en el await.
      datos.ignore();

      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      await recognizer.close();
      // Con el texto ya extraído la foto sobra: se borra ya.
      await _borrarImagen(imagePath);

      // `result.text` concatena el texto por "bloques" tal y como los agrupa
      // ML Kit, que no siempre coincide con el orden real de las filas del
      // ticket (p.ej. puede juntar primero todos los nombres de producto y
      // luego, aparte, todos los precios). Reconstruimos el orden real de
      // lectura a partir de la posición (x, y) de cada línea reconocida.
      final rawText = _reconstructReadingOrder(result);

      final (categories, aprendidas) = await datos;
      final (:items, :descartadas) =
          _buildLineItems(rawText, ProductClassifier(categorias: categories, aprendidas: aprendidas));

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ConfirmTicketScreen(
            repository: widget.repository,
            items: items,
            descartadas: descartadas,
            esEscaneo: true,
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = 'No se ha podido leer el ticket: $e');
    } finally {
      // La imagen nunca se sube ni se guarda: se borra en cuanto se ha
      // extraído el texto, incluso si algo falla por el camino.
      if (imagePath != null) await _borrarImagen(imagePath);
    }
  }

  Future<void> _borrarImagen(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  /// Reconstruye el texto del ticket en su orden visual real (arriba a
  /// abajo, izquierda a derecha por fila) a partir de las coordenadas de cada
  /// línea reconocida, en vez de fiarnos del orden de "bloques" de ML Kit.
  /// Así, cuando la descripción de un producto y su precio quedan en
  /// columnas separadas (columna izquierda de nombres, columna derecha de
  /// precios), se recomponen en la misma fila en vez de quedar todos los
  /// nombres seguidos y luego todos los precios.
  String _reconstructReadingOrder(RecognizedText result) {
    final lines = [for (final block in result.blocks) ...block.lines]
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final rows = <List<TextLine>>[];
    for (final line in lines) {
      if (rows.isNotEmpty) {
        // Comparamos contra la PRIMERA línea de la fila (referencia fija),
        // nunca contra el rango acumulado de toda la fila: si comparásemos
        // contra un rango que solo puede crecer, un ligero solape entre dos
        // líneas consecutivas iría inflando la fila hasta poder llegar a
        // tragarse el ticket entero.
        final anchor = rows.last.first;
        final overlap = min(anchor.boundingBox.bottom, line.boundingBox.bottom) - max(anchor.boundingBox.top, line.boundingBox.top);
        final minHeight = min(anchor.boundingBox.height, line.boundingBox.height);
        if (overlap > minHeight * 0.4) {
          rows.last.add(line);
          continue;
        }
      }
      rows.add([line]);
    }

    return rows.map((row) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      return row.map((l) => l.text).join('   ');
    }).join('\n');
  }

  /// Convierte el texto en líneas y le pone a cada una la categoría que
  /// propone el clasificador. Las que se parecen a algo que ya se quitó otras
  /// veces (total, forma de pago...) van aparte, en [descartadas], para poder
  /// recuperarlas si no tocaba.
  ({List<TicketLineItem> items, List<TicketLineItem> descartadas}) _buildLineItems(
    String rawText,
    ProductClassifier clasificador,
  ) {
    final items = <TicketLineItem>[];
    final descartadas = <TicketLineItem>[];
    for (final parsed in parseReceiptLines(rawText)) {
      final alPeso = parsed.pesoGramos != null;
      final item = TicketLineItem(
        textoOriginal: parsed.descripcion,
        textoEscaneado: parsed.descripcion,
        precioTotal: parsed.precioTotal,
        pesoGramos: parsed.pesoGramos,
        alPeso: alPeso,
        // Si el ticket trae un peso detectado, mostramos el campo de peso
        // desde ya; en cuanto se asigne categoría, su trackWeight manda.
        trackWeight: alPeso,
      );

      final guess = clasificador.classify(parsed.descripcion, alPeso: alPeso);
      if (guess != null && guess.noProducto) {
        descartadas.add(item);
        continue;
      }
      final categoria = guess?.categoria;
      if (categoria != null) {
        item.categoriaId = categoria.id;
        item.grupo = categoria.grupo;
        item.productoNormalizado = categoria.nombre;
        item.trackWeight = categoria.trackWeight;
        if (guess!.certeza == Certeza.probable) item.categoriaIdSugerida = categoria.id;
      }
      items.add(item);
    }
    return (items: items, descartadas: descartadas);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _captureAndProcess,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              )
            : const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Leyendo el ticket...'),
                ],
              ),
      ),
    );
  }
}
