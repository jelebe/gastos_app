import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/ticket_line_item.dart';
import '../services/household_repository.dart';
import '../widgets/category_picker_sheet.dart';

class ConfirmTicketScreen extends StatefulWidget {
  const ConfirmTicketScreen({super.key, required this.repository, required this.items});

  final HouseholdRepository repository;
  final List<TicketLineItem> items;

  @override
  State<ConfirmTicketScreen> createState() => _ConfirmTicketScreenState();
}

class _ConfirmTicketScreenState extends State<ConfirmTicketScreen> {
  final List<TicketLineItem> _items = [];
  final _comercioController = TextEditingController();
  DateTime _fecha = DateTime.now();
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
    setState(() {
      item.categoriaId = categoria.id;
      item.grupo = categoria.grupo;
      item.productoNormalizado = categoria.nombre;
      item.trackWeight = categoria.trackWeight;
      if (!categoria.trackWeight) item.pesoGramos = null;
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

  bool get _canSave =>
      _items.isNotEmpty && _items.every((i) => i.isCategorized && i.precioTotal != null && i.precioTotal! > 0);

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final toSave = <({String textoOriginal, double precioTotal, Category categoria, double? pesoGramos})>[];
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

      await widget.repository.saveTicket(
        items: toSave,
        importeTotal: _total,
        comercio: _comercioController.text.trim().isEmpty ? null : _comercioController.text.trim(),
        fecha: _fecha,
      );

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar ticket')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _comercioController,
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
          const SizedBox(height: 20),
          Text('Líneas del ticket', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final item in _items) _LineItemCard(
            key: ValueKey(item),
            item: item,
            onTapCategory: () => _pickCategory(item),
            onChangedPrecio: (v) => setState(() => item.precioTotal = v),
            onChangedPeso: (v) => setState(() => item.pesoGramos = v),
            onDelete: () => setState(() => _items.remove(item)),
          ),
          const SizedBox(height: 16),
          Text(
            'Total: ${_total.toStringAsFixed(2)} €',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: (_canSave && !_saving) ? _save : null,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Guardar ticket'),
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
    required this.onChangedPrecio,
    required this.onChangedPeso,
    required this.onDelete,
  });

  final TicketLineItem item;
  final VoidCallback onTapCategory;
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
                  child: Text(item.textoOriginal, style: Theme.of(context).textTheme.bodySmall),
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
