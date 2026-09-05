import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/ticket_line_item.dart';
import '../services/household_repository.dart';
import '../utils/text_normalizer.dart';
import '../widgets/category_picker_sheet.dart';

class ConfirmTicketScreen extends StatefulWidget {
  const ConfirmTicketScreen({
    super.key,
    required this.repository,
    required this.items,
    this.transactionId,
    this.comercioInicial,
    this.fechaInicial,
    this.comentarioInicial,
    this.pagadoPorInicial,
    this.compartidoInicial = true,
  });

  final HouseholdRepository repository;
  final List<TicketLineItem> items;

  /// Si no es nulo, se está editando un ticket ya guardado (en vez de crear
  /// uno nuevo): al guardar se sustituye en lugar de añadir otro.
  final String? transactionId;
  final String? comercioInicial;
  final DateTime? fechaInicial;
  final String? comentarioInicial;
  final String? pagadoPorInicial;
  final bool compartidoInicial;

  bool get isEditing => transactionId != null;

  @override
  State<ConfirmTicketScreen> createState() => _ConfirmTicketScreenState();
}

class _ConfirmTicketScreenState extends State<ConfirmTicketScreen> {
  final List<TicketLineItem> _items = [];
  late final _comercioController = TextEditingController(text: widget.comercioInicial);
  late final _comentarioController = TextEditingController(text: widget.comentarioInicial);
  late DateTime _fecha = widget.fechaInicial ?? DateTime.now();
  late String? _pagadoPor = widget.pagadoPorInicial;
  late bool _compartido = widget.compartidoInicial;
  List<Category> _categories = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _items.addAll(widget.items);
    widget.repository.loadCategories().then((c) => setState(() => _categories = c));
  }

  double get _total => _items.fold(0, (sum, item) => sum + (item.precioTotal ?? 0));

  Future<void> _pickCategory(TicketLineItem item) async {
    final categoria = await showCategoryPicker(context, categories: _categories, repository: widget.repository);
    if (categoria == null) return;
    final nombre = normalizeLine(item.textoOriginal);
    setState(() {
      for (final otro in _items) {
        // Mismo producto repetido (p.ej. "leche" x4 tras explotar un "4x")
        // que todavía no tiene categoría: se la asignamos también, para no
        // tener que elegirla una a una.
        final esElMismo = otro == item;
        final esRepetidoSinCategoria =
            !otro.isCategorized && nombre.isNotEmpty && normalizeLine(otro.textoOriginal) == nombre;
        if (!esElMismo && !esRepetidoSinCategoria) continue;

        otro.categoriaId = categoria.id;
        otro.grupo = categoria.grupo;
        otro.productoNormalizado = categoria.nombre;
        otro.trackWeight = categoria.trackWeight;
        if (!categoria.trackWeight) otro.pesoGramos = null;
      }
    });
    if (!_categories.any((c) => c.id == categoria.id)) {
      setState(() => _categories = [..._categories, categoria]);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _fecha = picked);
  }

  /// Si algo falta, devuelve el mensaje a mostrar; si todo está listo, `null`.
  String? get _validationError {
    if (_pagadoPor == null) return 'Elige quién ha pagado.';
    if (_items.isEmpty) return 'Añade al menos un producto.';
    if (_items.any((i) => i.textoOriginal.trim().isEmpty)) return 'Ponle nombre a todos los productos.';
    if (_items.any((i) => !i.isCategorized)) return 'Elige una categoría para cada producto.';
    if (_items.any((i) => i.precioTotal == null || i.precioTotal! <= 0)) {
      return 'Pon un precio mayor que 0 en cada producto.';
    }
    return null;
  }

  Future<void> _save() async {
    final error = _validationError;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    setState(() => _saving = true);
    try {
      final toSave = <TicketItemInput>[];
      for (final item in _items) {
        final categoria = _categories.firstWhere((c) => c.id == item.categoriaId);
        toSave.add((
          textoOriginal: item.textoOriginal,
          precioTotal: item.precioTotal!,
          categoria: categoria,
          pesoGramos: item.pesoGramos,
        ));
        await widget.repository.learnAlias(rawText: item.textoOriginal, categoria: categoria);
      }

      final comercio = _comercioController.text.trim().isEmpty ? null : _comercioController.text.trim();
      final comentario = _comentarioController.text.trim().isEmpty ? null : _comentarioController.text.trim();
      if (widget.isEditing) {
        await widget.repository.updateTicket(
          transactionId: widget.transactionId!,
          items: toSave,
          importeTotal: _total,
          comercio: comercio,
          fecha: _fecha,
          nota: comentario,
          pagadoPor: _pagadoPor!,
          compartido: _compartido,
        );
      } else {
        await widget.repository.saveTicket(
          items: toSave,
          importeTotal: _total,
          comercio: comercio,
          fecha: _fecha,
          nota: comentario,
          pagadoPor: _pagadoPor!,
          compartido: _compartido,
        );
      }

      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se ha podido guardar: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  void dispose() {
    _comercioController.dispose();
    _comentarioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isEditing ? 'Editar ticket' : 'Confirmar ticket')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _comercioController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Tienda (opcional)'),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Fecha', suffixIcon: Icon(Icons.calendar_today)),
              child: Text('${_fecha.day}/${_fecha.month}/${_fecha.year}'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _comentarioController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Comentario (opcional)'),
          ),
          const SizedBox(height: 16),
          Text('¿Quién ha pagado?', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Cano', label: Text('Cano')),
              ButtonSegment(value: 'Cana', label: Text('Cana')),
              ButtonSegment(value: 'Ambos', label: Text('Ambos')),
            ],
            selected: _pagadoPor == null ? const {} : {_pagadoPor!},
            emptySelectionAllowed: true,
            onSelectionChanged: (v) => setState(() => _pagadoPor = v.first),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Gasto compartido'),
            subtitle: const Text('Si lo desmarcas, no contará en el reparto por persona'),
            value: _compartido,
            onChanged: (v) => setState(() => _compartido = v),
          ),
          const SizedBox(height: 20),
          Text('Líneas del ticket', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Añade un producto con el botón de abajo.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
            ),
          for (final item in _items) _LineItemCard(
            key: ValueKey(item),
            item: item,
            onTapCategory: () => _pickCategory(item),
            onChangedDescripcion: (v) => item.textoOriginal = v,
            onChangedPrecio: (v) => setState(() => item.precioTotal = v),
            onChangedPeso: (v) => setState(() => item.pesoGramos = v),
            onDelete: () => setState(() => _items.remove(item)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() => _items.add(TicketLineItem(textoOriginal: ''))),
            icon: const Icon(Icons.add),
            label: const Text('Añadir producto'),
          ),
          const SizedBox(height: 16),
          Text(
            'Total: ${_total.toStringAsFixed(2)} €',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(widget.isEditing ? 'Guardar cambios' : 'Guardar ticket'),
          ),
        ],
      ),
    );
  }
}

class _LineItemCard extends StatelessWidget {
  const _LineItemCard({
    super.key,
    required this.item,
    required this.onTapCategory,
    required this.onChangedDescripcion,
    required this.onChangedPrecio,
    required this.onChangedPeso,
    required this.onDelete,
  });

  final TicketLineItem item;
  final VoidCallback onTapCategory;
  final ValueChanged<String> onChangedDescripcion;
  final ValueChanged<double?> onChangedPrecio;
  final ValueChanged<double?> onChangedPeso;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: item.textoOriginal,
                    style: Theme.of(context).textTheme.bodySmall,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Producto', isDense: true),
                    onChanged: onChangedDescripcion,
                  ),
                ),
                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onDelete),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ActionChip(
                  avatar: Icon(item.isCategorized ? Icons.check_circle : Icons.error_outline,
                      size: 18, color: item.isCategorized ? Colors.green : Colors.orange),
                  label: Text(item.isCategorized ? '${item.grupo} · ${item.productoNormalizado}' : 'Elegir categoría'),
                  onPressed: onTapCategory,
                ),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    initialValue: item.precioTotal?.toStringAsFixed(2),
                    decoration: const InputDecoration(labelText: 'Precio (€)', isDense: true),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) => onChangedPrecio(double.tryParse(v.replaceAll(',', '.'))),
                  ),
                ),
                if (item.trackWeight)
                  SizedBox(
                    width: 110,
                    child: TextFormField(
                      initialValue: item.pesoGramos?.toStringAsFixed(0),
                      decoration: const InputDecoration(labelText: 'Peso (g)', isDense: true),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => onChangedPeso(double.tryParse(v)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
