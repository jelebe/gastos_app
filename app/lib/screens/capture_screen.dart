import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../models/category.dart';
import '../models/ticket_line_item.dart';
import '../services/household_repository.dart';
import '../utils/text_normalizer.dart';
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

      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      await recognizer.close();

      final categories = await widget.repository.loadCategories();
      final items = await _buildLineItems(result.text, categories);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ConfirmTicketScreen(repository: widget.repository, items: items),
        ),
      );
    } catch (e) {
      setState(() => _error = 'No se ha podido leer el ticket: $e');
    } finally {
      // La imagen nunca se sube ni se guarda: se borra en cuanto se ha
      // extraído el texto, incluso si algo falla por el camino.
      if (imagePath != null) {
        final file = File(imagePath);
        if (await file.exists()) await file.delete();
      }
    }
  }

  Future<List<TicketLineItem>> _buildLineItems(String rawText, List<Category> categories) async {
    final items = <TicketLineItem>[];
    for (final rawLine in rawText.split('\n')) {
      final line = rawLine.trim();
      if (line.length < 3) continue;

      final (:descripcion, :precio) = splitDescriptionAndPrice(line);
      final item = TicketLineItem(textoOriginal: descripcion, precioTotal: precio);

      final match = await widget.repository.matchLine(descripcion, categories);
      if (match != null) {
        item.categoriaId = match.categoria.id;
        item.grupo = match.categoria.grupo;
        item.productoNormalizado = match.categoria.nombre;
        item.trackWeight = match.categoria.trackWeight;
      }
      items.add(item);
    }
    return items;
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
