import 'package:flutter/material.dart';

import '../models/category.dart';
import '../services/household_repository.dart';
import '../utils/text_normalizer.dart';

/// Grupos de términos que deben encontrarse entre sí en el buscador de
/// categorías, aunque no compartan ninguna letra en común (p.ej. buscar
/// "sueldo" también debe encontrar "Nómina"). Los términos van sin tilde y en
/// mayúsculas porque se comparan ya normalizados con [normalizeLine].
const _synonymGroups = [
  ['SUELDO', 'NOMINA', 'SALARIO', 'PAGA'],
  ['SUPERMERCADO', 'SUPER', 'COMPRA'],
  ['RESTAURANTE', 'BAR', 'COMER FUERA', 'CENA FUERA'],
  ['GASOLINA', 'COMBUSTIBLE', 'DIESEL'],
  ['MOVIL', 'TELEFONO', 'CELULAR'],
  ['LUZ', 'ELECTRICIDAD'],
  ['ALQUILER', 'RENTA', 'HIPOTECA'],
  ['TRANSPORTE', 'BUS', 'METRO', 'AUTOBUS'],
];

/// Amplía la búsqueda con los sinónimos de cualquier grupo que roce la
/// consulta (por prefijo/substring en cualquier dirección).
List<String> _expandSearchTerms(String normalizedQuery) {
  if (normalizedQuery.isEmpty) return const [];
  final terms = {normalizedQuery};
  for (final group in _synonymGroups) {
    if (group.any((term) => term.contains(normalizedQuery) || normalizedQuery.contains(term))) {
      terms.addAll(group);
    }
  }
  return terms.toList();
}

/// Filtra [categories] por [query] sobre nombre y grupo: sin distinguir
/// tildes/mayúsculas y ampliando la búsqueda con sinónimos conocidos (p.ej.
/// "sueldo" encuentra "Nómina"). Con [query] vacío devuelve todas.
List<Category> filterCategories(List<Category> categories, String query) {
  final normalizedQuery = normalizeLine(query);
  if (normalizedQuery.isEmpty) return categories;
  final searchTerms = _expandSearchTerms(normalizedQuery);
  return categories.where((c) {
    final nombre = normalizeLine(c.nombre);
    final grupo = normalizeLine(c.grupo);
    return searchTerms.any((t) => nombre.contains(t) || grupo.contains(t));
  }).toList();
}

/// Selector de categoría: buscador sobre las categorías existentes, con
/// opción de crear una nueva si de verdad no hay ninguna que encaje.
///
/// Si se indica [filterTipo] ("gasto" o "ingreso"), solo se listan y se
/// pueden crear categorías de ese tipo (p.ej. al registrar un ingreso no
/// tiene sentido ofrecer categorías de gasto como "Alimentación").
Future<Category?> showCategoryPicker(
  BuildContext context, {
  required List<Category> categories,
  required HouseholdRepository repository,
  String? filterTipo,
}) {
  final visibles = filterTipo == null ? categories : categories.where((c) => c.tipo == filterTipo).toList();
  return showModalBottomSheet<Category>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _CategoryPickerSheet(categories: visibles, repository: repository, tipo: filterTipo ?? 'gasto'),
  );
}

/// Diálogo para crear una categoría nueva, reutilizable tanto desde el
/// selector de categoría como desde la pestaña de Categorías.
Future<Category?> showCreateCategoryDialog(
  BuildContext context, {
  required List<Category> categories,
  required HouseholdRepository repository,
  String prefillNombre = '',
  String tipoInicial = 'gasto',
}) {
  final existingGrupos = {for (final c in categories) c.grupo}.toList()..sort();
  final grupoController = TextEditingController();
  final nombreController = TextEditingController(text: prefillNombre);
  String tipo = tipoInicial;
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
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nombre (ej. Detergente)'),
              ),
              const SizedBox(height: 12),
              Autocomplete<String>(
                optionsBuilder: (v) => v.text.isEmpty
                    ? existingGrupos
                    : existingGrupos.where((g) => normalizeLine(g).contains(normalizeLine(v.text))),
                onSelected: (v) => grupoController.text = v,
                fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                  controller.addListener(() => grupoController.text = controller.text);
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    textCapitalization: TextCapitalization.sentences,
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
              final categoria = await repository.createCategory(
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

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({required this.categories, required this.repository, required this.tipo});

  final List<Category> categories;
  final HouseholdRepository repository;
  final String tipo;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = filterCategories(widget.categories, _query);

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
                controller: _searchController,
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
                        final created = await showCreateCategoryDialog(
                          context,
                          categories: widget.categories,
                          repository: widget.repository,
                          prefillNombre: _query,
                          tipoInicial: widget.tipo,
                        );
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
}
