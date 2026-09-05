import 'package:flutter/material.dart';

import '../models/category.dart';
import '../services/household_repository.dart';

/// Selector de categoría: buscador sobre las categorías existentes, con
/// opción de crear una nueva si de verdad no hay ninguna que encaje.
Future<Category?> showCategoryPicker(
  BuildContext context, {
  required List<Category> categories,
  required HouseholdRepository repository,
}) {
  return showModalBottomSheet<Category>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _CategoryPickerSheet(categories: categories, repository: repository),
  );
}

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({required this.categories, required this.repository});

  final List<Category> categories;
  final HouseholdRepository repository;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final filtered = widget.categories
        .where((c) => c.nombre.toLowerCase().contains(query) || c.grupo.toLowerCase().contains(query))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Buscar categoría',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: filtered.length + 1,
                itemBuilder: (context, index) {
                  if (index == filtered.length) {
                    return ListTile(
                      leading: const Icon(Icons.add),
                      title: Text(
                        _query.isEmpty ? 'Crear categoría nueva' : 'Crear "$_query" como categoría nueva',
                      ),
                      onTap: () async {
                        final created = await _showCreateCategoryDialog(context, _query);
                        if (created != null && context.mounted) Navigator.of(context).pop(created);
                      },
                    );
                  }
                  final categoria = filtered[index];
                  return ListTile(
                    title: Text(categoria.nombre),
                    subtitle: Text(categoria.grupo),
                    onTap: () => Navigator.of(context).pop(categoria),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<Category?> _showCreateCategoryDialog(BuildContext context, String prefillNombre) {
    final existingGrupos = {for (final c in widget.categories) c.grupo}.toList()..sort();
    final grupoController = TextEditingController();
    final nombreController = TextEditingController(text: prefillNombre);
    String tipo = 'gasto';
    bool trackWeight = false;
    String unidadDefault = 'unidad';

    return showDialog<Category>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nueva categoría'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nombreController,
                  decoration: const InputDecoration(labelText: 'Nombre (ej. Detergente)'),
                ),
                const SizedBox(height: 12),
                Autocomplete<String>(
                  optionsBuilder: (v) => v.text.isEmpty
                      ? existingGrupos
                      : existingGrupos.where((g) => g.toLowerCase().contains(v.text.toLowerCase())),
                  onSelected: (v) => grupoController.text = v,
                  fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                    controller.addListener(() => grupoController.text = controller.text);
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(labelText: 'Grupo (ej. Limpieza)'),
                    );
                  },
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'gasto', label: Text('Gasto')),
                    ButtonSegment(value: 'ingreso', label: Text('Ingreso')),
                  ],
                  selected: {tipo},
                  onSelectionChanged: (v) => setDialogState(() => tipo = v.first),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: unidadDefault,
                  decoration: const InputDecoration(labelText: 'Unidad'),
                  items: const [
                    DropdownMenuItem(value: 'unidad', child: Text('Unidad')),
                    DropdownMenuItem(value: 'kg', child: Text('Kilogramos')),
                    DropdownMenuItem(value: 'L', child: Text('Litros')),
                  ],
                  onChanged: (v) => setDialogState(() {
                    unidadDefault = v!;
                    trackWeight = unidadDefault != 'unidad';
                  }),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Seguir precio por kilo/litro'),
                  value: trackWeight,
                  onChanged: unidadDefault == 'unidad' ? null : (v) => setDialogState(() => trackWeight = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                if (nombreController.text.trim().isEmpty || grupoController.text.trim().isEmpty) return;
                final categoria = await widget.repository.createCategory(
                  grupo: grupoController.text.trim(),
                  nombre: nombreController.text.trim(),
                  tipo: tipo,
                  trackWeight: trackWeight,
                  unidadDefault: unidadDefault,
                );
                if (context.mounted) Navigator.of(context).pop(categoria);
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }
}
