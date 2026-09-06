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
  String prefillGrupo = '',
  String tipoInicial = 'gasto',
}) {
  final existingGrupos = {for (final c in categories) c.grupo}.toList()..sort();
  final grupoController = TextEditingController(text: prefillGrupo);
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
                initialValue: TextEditingValue(text: prefillGrupo),
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

/// Selector en dos pasos: primero la lista de grupos, y al entrar en uno, sus
/// categorías (con vuelta atrás). Con la lista entera de categorías de golpe
/// era imposible encontrar nada sin escribir; así se puede llegar a mano.
///
/// El buscador sigue estando por encima de los dos niveles: si se busca desde
/// la lista de grupos se buscan categorías de todos ellos, y si se busca ya
/// dentro de un grupo, solo dentro de ese.
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

  /// Grupo en el que se ha entrado; `null` mientras se ve la lista de grupos.
  String? _grupo;

  /// Si todas las categorías disponibles caen en un mismo grupo (pasa al
  /// registrar un ingreso, donde solo hay "Ingresos"), la lista de grupos no
  /// decide nada: se entra directamente y no se ofrece volver a ella.
  late final bool _grupoUnico = _grupos.length == 1;

  @override
  void initState() {
    super.initState();
    if (_grupoUnico) _grupo = _grupos.first.nombre;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openGrupo(String grupo) {
    _searchController.clear();
    setState(() {
      _grupo = grupo;
      _query = '';
    });
  }

  void _backToGrupos() {
    _searchController.clear();
    setState(() {
      _grupo = null;
      _query = '';
    });
  }

  /// Los grupos que existen entre las categorías disponibles, con cuántas
  /// tiene cada uno, en orden alfabético.
  List<({String nombre, int cuantas})> get _grupos {
    final cuenta = <String, int>{};
    for (final c in widget.categories) {
      cuenta[c.grupo] = (cuenta[c.grupo] ?? 0) + 1;
    }
    final nombres = cuenta.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [for (final n in nombres) (nombre: n, cuantas: cuenta[n]!)];
  }

  Future<void> _createCategory() async {
    final created = await showCreateCategoryDialog(
      context,
      categories: widget.categories,
      repository: widget.repository,
      prefillNombre: _query,
      prefillGrupo: _grupo ?? '',
      tipoInicial: widget.tipo,
    );
    if (created != null && mounted) Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    final buscando = _query.trim().isNotEmpty;
    // Dentro de un grupo se busca solo en él; desde la lista de grupos, en
    // todas las categorías (para no obligar a adivinar en qué grupo cae algo).
    final ambito = _grupo == null ? widget.categories : widget.categories.where((c) => c.grupo == _grupo).toList();
    final resultados = buscando ? filterCategories(ambito, _query) : ambito;

    return PopScope(
      // Estando dentro de un grupo, "atrás" vuelve a la lista de grupos en vez
      // de cerrar el selector entero.
      canPop: _grupo == null || _grupoUnico,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _backToGrupos();
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 16, 4),
                child: Row(
                  children: [
                    if (_grupo != null && !_grupoUnico)
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Volver a los grupos',
                        onPressed: _backToGrupos,
                      )
                    else
                      const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _grupo ?? 'Elegir categoría',
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: _grupo == null ? 'Buscar categoría' : 'Buscar en $_grupo',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: (_grupo == null && !buscando)
                    ? _GrupoList(grupos: _grupos, controller: scrollController, onTap: _openGrupo)
                    : _CategoriaList(
                        categorias: resultados,
                        controller: scrollController,
                        mostrarGrupo: _grupo == null,
                        crearLabel: buscando ? 'Crear "$_query" como categoría nueva' : 'Crear categoría nueva',
                        onCrear: _createCategory,
                        onTap: (categoria) => Navigator.of(context).pop(categoria),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GrupoList extends StatelessWidget {
  const _GrupoList({required this.grupos, required this.controller, required this.onTap});

  final List<({String nombre, int cuantas})> grupos;
  final ScrollController controller;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (grupos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Todavía no hay ninguna categoría. Escribe un nombre arriba para crear la primera.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: controller,
      itemCount: grupos.length,
      itemBuilder: (context, index) {
        final grupo = grupos[index];
        return ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(grupo.nombre),
          subtitle: Text('${grupo.cuantas} ${grupo.cuantas == 1 ? 'categoría' : 'categorías'}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onTap(grupo.nombre),
        );
      },
    );
  }
}

class _CategoriaList extends StatelessWidget {
  const _CategoriaList({
    required this.categorias,
    required this.controller,
    required this.mostrarGrupo,
    required this.crearLabel,
    required this.onCrear,
    required this.onTap,
  });

  final List<Category> categorias;
  final ScrollController controller;

  /// Al buscar desde la lista de grupos los resultados vienen de sitios
  /// distintos, así que cada uno necesita decir de qué grupo sale; dentro de
  /// un grupo sobra, porque ya está en la cabecera.
  final bool mostrarGrupo;
  final String crearLabel;
  final VoidCallback onCrear;
  final ValueChanged<Category> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      itemCount: categorias.length + 1,
      itemBuilder: (context, index) {
        if (index == categorias.length) {
          return ListTile(
            leading: const Icon(Icons.add),
            title: Text(crearLabel),
            onTap: onCrear,
          );
        }
        final categoria = categorias[index];
        return ListTile(
          title: Text(categoria.nombre),
          subtitle: mostrarGrupo ? Text(categoria.grupo) : null,
          onTap: () => onTap(categoria),
        );
      },
    );
  }
}
