import 'package:flutter/material.dart';

import '../models/store.dart';
import '../services/household_repository.dart';
import '../utils/text_normalizer.dart';

/// Lo que devuelve el selector: el establecimiento elegido, o que se ha
/// quitado el que había.
///
/// Hacen falta los dos casos distintos de "nada": cerrar la hoja sin tocar
/// nada (devuelve `null` y no cambia lo que hubiera) y elegir "sin tienda"
/// (devuelve un [StoreChoice] con [nombre] nulo, que sí lo borra).
typedef StoreChoice = ({String? nombre});

/// Selector de establecimiento: la lista del hogar por grupos, con buscador, y
/// la opción de añadir uno nuevo si de verdad no está.
///
/// Se elige de una lista en vez de escribirse cada vez para que el nombre sea
/// siempre el mismo: es lo que permite luego comparar precios entre tiendas.
Future<StoreChoice?> showStorePicker(
  BuildContext context, {
  required HouseholdRepository repository,
  String? actual,
}) {
  return showModalBottomSheet<StoreChoice>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _StorePickerSheet(repository: repository, actual: actual),
  );
}

class _StorePickerSheet extends StatefulWidget {
  const _StorePickerSheet({required this.repository, this.actual});

  final HouseholdRepository repository;
  final String? actual;

  @override
  State<_StorePickerSheet> createState() => _StorePickerSheetState();
}

class _StorePickerSheetState extends State<_StorePickerSheet> {
  final _searchController = TextEditingController();
  late final Future<List<Store>> _future = widget.repository.loadStores();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _crear(String nombre, {String? grupo}) async {
    final limpio = nombre.trim();
    if (limpio.isEmpty) return;
    try {
      final store = await widget.repository.createStore(limpio, grupo: grupo);
      if (mounted) Navigator.of(context).pop((nombre: store.nombre));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se ha podido añadir: $e')));
      }
    }
  }

  /// Al añadir desde aquí se pregunta el grupo, pero sin obligar: en mitad de
  /// guardar un ticket, parar a clasificar es justo lo que no toca. Lo que se
  /// quede suelto se coloca luego desde la pantalla de Tiendas.
  Future<void> _preguntarGrupoYCrear(String nombre, List<Store> todas) async {
    final grupos = {for (final t in todas) if (t.grupo != null) t.grupo!}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final grupo = await showDialog<String?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('¿Qué es "$nombre"?'),
        children: [
          for (final g in grupos)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(g),
              child: Text(g),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Sin grupo, ya lo coloco luego'),
          ),
        ],
      ),
    );
    if (grupo == null || !mounted) return;
    await _crear(nombre, grupo: grupo.isEmpty ? null : grupo);
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
      child: FutureBuilder<List<Store>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return SizedBox(height: 120, child: Center(child: Text('Error: ${snapshot.error}')));
          }
          if (!snapshot.hasData) {
            return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
          }

          final todos = snapshot.data!;
          final clave = normalizeLine(_query);
          // Buscando se lista plano: los grupos ayudan a navegar, pero estorban
          // cuando ya has escrito lo que buscas.
          final buscando = clave.isNotEmpty;
          final visibles = buscando
              ? todos
                  .where((s) =>
                      normalizeLine(s.nombre).contains(clave) ||
                      normalizeLine(s.grupoVisible).contains(clave))
                  .toList()
              : todos;
          final puedeCrear = buscando && !todos.any((s) => normalizeLine(s.nombre) == clave);

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('¿Dónde has comprado?', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                autofocus: todos.isEmpty,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Buscar o añadir',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
                onSubmitted: puedeCrear ? (v) => _preguntarGrupoYCrear(v.trim(), todos) : null,
              ),
              const SizedBox(height: 8),
              if (puedeCrear)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.add),
                  title: Text('Añadir "${_query.trim()}"'),
                  onTap: () => _preguntarGrupoYCrear(_query.trim(), todos),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (widget.actual != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.close),
                        title: const Text('Sin tienda'),
                        onTap: () => Navigator.of(context).pop((nombre: null)),
                      ),
                    if (visibles.isEmpty && !puedeCrear)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Todavía no hay tiendas en la lista. Escribe el nombre para añadir la primera.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    if (buscando)
                      for (final store in visibles) _FilaTienda(store: store, actual: widget.actual)
                    else
                      for (final MapEntry(key: grupo, value: tiendas) in agrupaTiendas(visibles))
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(grupo),
                          subtitle: Text('${tiendas.length} ${tiendas.length == 1 ? 'tienda' : 'tiendas'}'),
                          // Abierto el grupo de la que está puesta, para no
                          // tener que buscarla al entrar a cambiarla.
                          initiallyExpanded: tiendas.any((t) => t.nombre == widget.actual),
                          children: [
                            for (final store in tiendas)
                              _FilaTienda(store: store, actual: widget.actual),
                          ],
                        ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilaTienda extends StatelessWidget {
  const _FilaTienda({required this.store, required this.actual});

  final Store store;
  final String? actual;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      selected: store.nombre == actual,
      title: Text(store.nombre),
      onTap: () => Navigator.of(context).pop((nombre: store.nombre)),
    );
  }
}
