import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/transaction_summary.dart';
import '../services/household_repository.dart';
import 'category_picker_sheet.dart';

/// Formulario para registrar (o editar, si se pasa [existing]) un ingreso
/// suelto: categoría, importe, fecha y una nota opcional. Devuelve `true` si
/// se ha guardado.
Future<bool> showAddIncomeSheet(
  BuildContext context, {
  required HouseholdRepository repository,
  required List<Category> categories,
  TransactionSummary? existing,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _AddIncomeSheet(repository: repository, categories: categories, existing: existing),
  );
  return saved ?? false;
}

class _AddIncomeSheet extends StatefulWidget {
  const _AddIncomeSheet({required this.repository, required this.categories, this.existing});

  final HouseholdRepository repository;
  final List<Category> categories;
  final TransactionSummary? existing;

  bool get isEditing => existing != null;

  @override
  State<_AddIncomeSheet> createState() => _AddIncomeSheetState();
}

class _AddIncomeSheetState extends State<_AddIncomeSheet> {
  Category? _categoria;
  late final _importeController = TextEditingController(
    text: widget.existing?.importeTotal.toStringAsFixed(2),
  );
  late final _notaController = TextEditingController(text: widget.existing?.nota);
  late DateTime _fecha = widget.existing?.fecha ?? DateTime.now();
  late String? _pagadoPor = widget.existing?.pagadoPor;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final categoriaId = widget.existing?.categoriaId;
    if (categoriaId != null) {
      for (final c in widget.categories) {
        if (c.id == categoriaId) {
          _categoria = c;
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _importeController.dispose();
    _notaController.dispose();
    super.dispose();
  }

  Future<void> _pickCategory() async {
    final categoria = await showCategoryPicker(
      context,
      categories: widget.categories,
      repository: widget.repository,
      filterTipo: 'ingreso',
    );
    if (categoria != null) setState(() => _categoria = categoria);
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
    if (_categoria == null) return 'Elige una categoría.';
    final importe = double.tryParse(_importeController.text.replaceAll(',', '.'));
    if (importe == null || importe <= 0) return 'Pon un importe mayor que 0.';
    return null;
  }

  Future<void> _save() async {
    final error = _validationError;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    final importe = double.parse(_importeController.text.replaceAll(',', '.'));
    setState(() => _saving = true);
    try {
      if (widget.isEditing) {
        await widget.repository.updateIncome(
          id: widget.existing!.id,
          categoria: _categoria!,
          importe: importe,
          fecha: _fecha,
          nota: _notaController.text,
          pagadoPor: _pagadoPor!,
        );
      } else {
        await widget.repository.saveIncome(
          categoria: _categoria!,
          importe: importe,
          fecha: _fecha,
          nota: _notaController.text,
          pagadoPor: _pagadoPor!,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se ha podido guardar: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.isEditing ? 'Editar ingreso' : 'Añadir ingreso', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          ActionChip(
            avatar: Icon(
              _categoria == null ? Icons.error_outline : Icons.check_circle,
              size: 18,
              color: _categoria == null ? Colors.orange : Colors.green,
            ),
            label: Text(_categoria?.nombre ?? 'Elegir categoría'),
            onPressed: _pickCategory,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _importeController,
            decoration: const InputDecoration(labelText: 'Importe (€)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            controller: _notaController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nota (opcional)'),
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
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(widget.isEditing ? 'Guardar cambios' : 'Guardar ingreso'),
          ),
        ],
      ),
    );
  }
}
