import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/store.dart';
import '../models/ticket_line_item.dart';
import '../models/transaction_summary.dart';
import '../services/household_repository.dart';
import '../utils/formato.dart';
import '../utils/text_normalizer.dart';
import '../widgets/add_income_sheet.dart';
import '../widgets/category_picker_sheet.dart';
import '../widgets/money_transfer_sheet.dart';
import '../widgets/month_selector.dart';
import '../widgets/update_dialog.dart';
import 'capture_screen.dart';
import 'confirm_ticket_screen.dart';
import 'dashboard_tab.dart';

enum _Section { inicio, ingresos, gastos, pases, categorias, tiendas }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repository = HouseholdRepository();
  _Section _section = _Section.inicio;

  @override
  void initState() {
    super.initState();
    // Se mira si hay versión nueva al entrar, una vez por arranque. Va tras
    // el primer frame porque necesita un contexto con Navigator montado, y no
    // se espera: si no hay red, la app sigue como si nada.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowUpdateDialog(context);
    });
    // La primera vez, lo aprendido se rellena con los tickets ya guardados:
    // mejor hacerlo al entrar que en mitad del primer escaneo.
    _repository.loadLearnedLines().ignore();
  }

  static const _titulos = {
    _Section.inicio: 'Inicio',
    _Section.ingresos: 'Ingresos',
    _Section.gastos: 'Gastos',
    _Section.pases: 'Pases de dinero',
    _Section.categorias: 'Categorías',
    _Section.tiendas: 'Tiendas',
  };

  /// Se cambia cada vez que se guarda o se borra algo, para que el dashboard
  /// (que carga sus datos una vez, no en vivo) los recalcule. Va como dato y
  /// no como `Key` a propósito: con una `Key` el widget se recreaba entero y
  /// perdía el mes que se estuviera mirando.
  int _dashboardTick = 0;

  void _refreshDashboard() => setState(() => _dashboardTick++);

  /// Para que el botón + pueda añadir una tienda estando en esa pestaña: el
  /// formulario vive dentro, con su propia recarga.
  final _storesKey = GlobalKey<_StoresTabState>();

  void _selectSection(_Section section) {
    Navigator.of(context).pop(); // cierra el drawer
    setState(() => _section = section);
  }

  Future<void> _showAddOptions(BuildContext context) async {
    final choice = await showModalBottomSheet<_AddChoice>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Escanear ticket'),
              onTap: () => Navigator.of(context).pop(_AddChoice.scan),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Manual'),
              subtitle: const Text('Un gasto suelto o un ticket tecleado a mano'),
              onTap: () => Navigator.of(context).pop(_AddChoice.manual),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Pasar dinero'),
              subtitle: const Text('Saldar la deuda, o darle dinero al otro si lo necesita'),
              onTap: () => Navigator.of(context).pop(_AddChoice.transfer),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;

    switch (choice) {
      case _AddChoice.scan:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CaptureScreen(repository: _repository)),
        );
      case _AddChoice.manual:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ConfirmTicketScreen(repository: _repository, items: <TicketLineItem>[]),
          ),
        );
      case _AddChoice.transfer:
        await showMoneyTransferSheet(context, repository: _repository);
    }
    _refreshDashboard();
  }

  Future<void> _addIncome(BuildContext context) async {
    final categories = await _repository.loadCategories();
    if (!context.mounted) return;
    await showAddIncomeSheet(context, repository: _repository, categories: categories);
    _refreshDashboard();
  }

  Future<void> _addTransfer(BuildContext context) async {
    await showMoneyTransferSheet(context, repository: _repository);
    _refreshDashboard();
  }

  Future<void> _editTransaction(TransactionSummary tx) async {
    if (tx.tipo == 'ingreso') {
      final categories = await _repository.loadCategories();
      if (!mounted) return;
      await showAddIncomeSheet(context, repository: _repository, categories: categories, existing: tx);
    } else {
      final categories = await _repository.loadCategories();
      final items = await _repository.loadTicketItems(tx.id, categories);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConfirmTicketScreen(
            repository: _repository,
            items: items,
            transactionId: tx.id,
            comercioInicial: tx.comercio,
            fechaInicial: tx.fecha,
            comentarioInicial: tx.nota,
            pagadoPorInicial: tx.pagadoPor,
            compartidoInicial: tx.compartido,
          ),
        ),
      );
    }
    _refreshDashboard();
  }

  Future<void> _addCategory(BuildContext context) async {
    final categories = await _repository.loadCategories();
    if (!context.mounted) return;
    await showCreateCategoryDialog(context, categories: categories, repository: _repository);
  }

  Future<void> _confirmDeleteCategory(Category categoria) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar categoría'),
        content: Text(
          '¿Seguro que quieres borrar "${categoria.nombre}" (${categoria.grupo})? '
          'Los gastos ya guardados no se ven afectados.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    try {
      await _repository.deleteCategory(categoria.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se ha podido borrar: $e')));
      }
    }
  }

  Future<void> _confirmDeleteTransaction(TransactionSummary tx) async {
    final esIngreso = tx.tipo == 'ingreso';
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          tx.esLiquidacion ? 'Borrar movimiento' : (esIngreso ? 'Borrar ingreso' : 'Borrar gasto'),
        ),
        content: Text(
          tx.esLiquidacion
              ? '${_efectoAlBorrar(tx)} No se puede deshacer.'
              : '¿Seguro que quieres borrarlo? No se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    try {
      await _repository.deleteTransaction(tx.id);
      _refreshDashboard();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se ha podido borrar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titulos[_section]!),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              const DrawerHeader(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text('Canogasto', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                ),
              ),
              _DrawerItem(
                icon: Icons.home_outlined,
                label: 'Inicio',
                selected: _section == _Section.inicio,
                onTap: () => _selectSection(_Section.inicio),
              ),
              _DrawerItem(
                icon: Icons.attach_money,
                label: 'Ingresos',
                selected: _section == _Section.ingresos,
                onTap: () => _selectSection(_Section.ingresos),
              ),
              _DrawerItem(
                icon: Icons.receipt_long_outlined,
                label: 'Gastos',
                selected: _section == _Section.gastos,
                onTap: () => _selectSection(_Section.gastos),
              ),
              _DrawerItem(
                icon: Icons.swap_horiz,
                label: 'Pases de dinero',
                selected: _section == _Section.pases,
                onTap: () => _selectSection(_Section.pases),
              ),
              _DrawerItem(
                icon: Icons.category_outlined,
                label: 'Categorías',
                selected: _section == _Section.categorias,
                onTap: () => _selectSection(_Section.categorias),
              ),
              _DrawerItem(
                icon: Icons.storefront_outlined,
                label: 'Tiendas',
                selected: _section == _Section.tiendas,
                onTap: () => _selectSection(_Section.tiendas),
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _Section.values.indexOf(_section),
        children: [
          DashboardTab(repository: _repository, refreshTick: _dashboardTick),
          _TransactionsList(
            repository: _repository,
            tipo: 'ingreso',
            onDelete: _confirmDeleteTransaction,
            onEdit: _editTransaction,
          ),
          _TransactionsList(
            repository: _repository,
            tipo: 'gasto',
            onDelete: _confirmDeleteTransaction,
            onEdit: _editTransaction,
          ),
          _TransactionsList(
            repository: _repository,
            tipo: 'liquidacion',
            onDelete: _confirmDeleteTransaction,
            onEdit: _editTransaction,
          ),
          _CategoriesTab(repository: _repository, onDeleteCategory: _confirmDeleteCategory),
          _StoresTab(repository: _repository, key: _storesKey),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => switch (_section) {
          _Section.ingresos => _addIncome(context),
          _Section.pases => _addTransfer(context),
          _Section.categorias => _addCategory(context),
          _Section.tiendas => _storesKey.currentState?.nuevaTienda() ?? Future.value(),
          _Section.inicio || _Section.gastos => _showAddOptions(context),
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

enum _AddChoice { scan, manual, transfer }

/// Qué le pasa a la deuda si se borra un movimiento de dinero: deshacerlo la
/// mueve al contrario de como la movió.
String _efectoAlBorrar(TransactionSummary tx) => tx.esPrestamo
    ? 'La deuda bajará ${euros(tx.importeTotal)}.'
    : 'La deuda volverá a subir ${euros(tx.importeTotal)}.';

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
      onTap: onTap,
    );
  }
}

class _CategoriesTab extends StatefulWidget {
  const _CategoriesTab({required this.repository, required this.onDeleteCategory});

  final HouseholdRepository repository;
  final ValueChanged<Category> onDeleteCategory;

  @override
  State<_CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends State<_CategoriesTab> {
  final _searchController = TextEditingController();
  // OJO: el stream se crea UNA sola vez aquí, no dentro de build(). Si se
  // llamara a watchCategories() en cada build (p.ej. al escribir en el
  // buscador), StreamBuilder vería un Stream distinto cada vez, se
  // resuscribiría de golpe y la lista entera (con el TextField dentro)
  // parpadearía a "cargando" en cada letra, cerrando el teclado.
  late final Stream<List<Category>> _categoriesStream = widget.repository.watchCategories();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Category>>(
      stream: _categoriesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final categories = filterCategories(snapshot.data!, _query);
        final grouped = <String, List<Category>>{};
        for (final categoria in categories) {
          grouped.putIfAbsent(categoria.grupo, () => []).add(categoria);
        }

        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Buscar categoría',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                '${categories.length} categorías',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final grupo in grouped.keys)
              ExpansionTile(
                title: Text(grupo),
                subtitle: Text('${grouped[grupo]!.length} categorías'),
                children: [
                  for (final categoria in grouped[grupo]!)
                    ListTile(
                      dense: true,
                      title: Text(categoria.nombre),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(categoria.unidadDefault),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            tooltip: 'Borrar categoría',
                            onPressed: () => widget.onDeleteCategory(categoria),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// La lista de tiendas del hogar, para dejarla limpia: se pueden marcar
/// varias y quitarlas de una vez, o renombrar una para fusionarla con otra.
///
/// Hace falta porque la lista se sembró con lo que hubiera escrito en el campo
/// libre de "tienda" de los tickets viejos, y ahí había de todo: nombres a
/// medias ("Ahorramás a0") y cosas que no eran tiendas ("Alquiler").
class _StoresTab extends StatefulWidget {
  const _StoresTab({required this.repository, super.key});

  final HouseholdRepository repository;

  @override
  State<_StoresTab> createState() => _StoresTabState();
}

class _StoresTabState extends State<_StoresTab> {
  late Future<List<Store>> _future = widget.repository.loadStores();
  final _seleccionadas = <String>{};

  void _recargar() => setState(() {
        _seleccionadas.clear();
        _future = widget.repository.loadStores();
      });

  void _avisar(String mensaje) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  /// Los grupos que ya existen, para ofrecerlos en vez de hacer teclearlos.
  List<String> _gruposDe(List<Store> tiendas) =>
      {for (final t in tiendas) if (t.grupo != null) t.grupo!}.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  /// Añade una tienda a mano. Lo llama el botón + de la pantalla.
  Future<void> nuevaTienda() async {
    final tiendas = await _future;
    if (!mounted) return;
    final datos = await _pedirDatos(titulo: 'Nueva tienda', grupos: _gruposDe(tiendas));
    if (datos == null) return;
    try {
      await widget.repository.createStore(datos.nombre, grupo: datos.grupo);
      _recargar();
    } catch (e) {
      _avisar('No se ha podido añadir: $e');
    }
  }

  Future<({String nombre, String? grupo})?> _pedirDatos({
    required String titulo,
    required List<String> grupos,
    String nombre = '',
    String? grupo,
  }) {
    final nombreController = TextEditingController(text: nombre);
    final grupoController = TextEditingController(text: grupo ?? '');
    return showDialog<({String nombre, String? grupo})>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreController,
              autofocus: nombre.isEmpty,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre (ej. Mercadona)'),
            ),
            const SizedBox(height: 12),
            // Autocompletado sobre los grupos que ya hay, igual que al crear
            // una categoría: se reutiliza el que exista en vez de inventar
            // "Bares" y "bar" por separado.
            Autocomplete<String>(
              initialValue: TextEditingValue(text: grupo ?? ''),
              optionsBuilder: (v) => v.text.isEmpty
                  ? grupos
                  : grupos.where((g) => g.toLowerCase().contains(v.text.toLowerCase())),
              onSelected: (v) => grupoController.text = v,
              fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                controller.addListener(() => grupoController.text = controller.text);
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Grupo (ej. Supermercados)'),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final n = nombreController.text.trim();
              if (n.isEmpty) return;
              final g = grupoController.text.trim();
              Navigator.of(context).pop((nombre: n, grupo: g.isEmpty ? null : g));
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _editar(Store store, List<Store> todas) async {
    final datos = await _pedirDatos(
      titulo: 'Editar tienda',
      grupos: _gruposDe(todas),
      nombre: store.nombre,
      grupo: store.grupo,
    );
    if (datos == null) return;
    if (datos.nombre == store.nombre && datos.grupo == store.grupo) return;
    try {
      final tickets = await widget.repository.renameStore(store.id, datos.nombre, grupo: datos.grupo);
      _recargar();
      _avisar(tickets == 0
          ? 'Guardada.'
          : 'Guardada, y $tickets ${tickets == 1 ? 'ticket actualizado' : 'tickets actualizados'}.');
    } catch (e) {
      _avisar('No se ha podido guardar: $e');
    }
  }

  Future<String?> _pedirGrupoNuevo() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Grupo nuevo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nombre del grupo (ej. Bares)'),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim().isEmpty ? null : v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              Navigator.of(context).pop(v.isEmpty ? null : v);
            },
            child: const Text('Mover'),
          ),
        ],
      ),
    );
  }

  Future<void> _moverSeleccionadas(List<Store> todas) async {
    final grupos = _gruposDe(todas);
    final grupo = await showDialog<String?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Mover ${_seleccionadas.length} a...'),
        children: [
          for (final g in grupos)
            SimpleDialogOption(onPressed: () => Navigator.of(context).pop(g), child: Text(g)),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Sin grupo'),
          ),
          SimpleDialogOption(
            onPressed: () async {
              final nuevo = await _pedirGrupoNuevo();
              if (context.mounted) Navigator.of(context).pop(nuevo);
            },
            child: const Text('Grupo nuevo...'),
          ),
        ],
      ),
    );
    if (grupo == null) return;
    try {
      await widget.repository.setStoreGroup(_seleccionadas.toList(), grupo.isEmpty ? null : grupo);
      _recargar();
    } catch (e) {
      _avisar('No se han podido mover: $e');
    }
  }

  Future<void> _borrarSeleccionadas(List<Store> todas) async {
    final cuantas = _seleccionadas.length;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(cuantas == 1 ? 'Quitar tienda' : 'Quitar $cuantas tiendas'),
        content: const Text(
          'Dejarán de salir al elegir tienda en un ticket. Los tickets ya guardados no se '
          'tocan: siguen con el nombre que tuvieran.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton.tonal(onPressed: () => Navigator.of(context).pop(true), child: const Text('Quitar')),
        ],
      ),
    );
    if (confirmado != true) return;

    try {
      await widget.repository.deleteStores(_seleccionadas.toList());
      _recargar();
    } catch (e) {
      _avisar('No se han podido quitar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Store>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final tiendas = snapshot.data!;
        if (tiendas.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No hay tiendas en la lista.\nPulsa + para añadir una, o añádelas sobre la marcha '
                'al confirmar un ticket.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        final todasMarcadas = _seleccionadas.length == tiendas.length;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _seleccionadas.isEmpty
                          ? '${tiendas.length} ${tiendas.length == 1 ? 'tienda' : 'tiendas'}'
                          : '${_seleccionadas.length} seleccionadas',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      if (todasMarcadas) {
                        _seleccionadas.clear();
                      } else {
                        _seleccionadas
                          ..clear()
                          ..addAll(tiendas.map((t) => t.id));
                      }
                    }),
                    child: Text(todasMarcadas ? 'Ninguna' : 'Todas'),
                  ),
                  if (_seleccionadas.isNotEmpty) ...[
                    IconButton(
                      icon: const Icon(Icons.drive_file_move_outlined),
                      tooltip: 'Mover a un grupo',
                      onPressed: () => _moverSeleccionadas(tiendas),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Quitar las seleccionadas',
                      onPressed: () => _borrarSeleccionadas(tiendas),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final MapEntry(key: grupo, value: delGrupo) in agrupaTiendas(tiendas))
                    ExpansionTile(
                      title: Text(grupo),
                      subtitle: Text('${delGrupo.length} ${delGrupo.length == 1 ? 'tienda' : 'tiendas'}'),
                      // Abierto si hay algo marcado dentro: si no, al marcar y
                      // plegar se perdería de vista lo seleccionado.
                      initiallyExpanded: delGrupo.any((t) => _seleccionadas.contains(t.id)),
                      children: [
                        for (final tienda in delGrupo)
                          CheckboxListTile(
                            value: _seleccionadas.contains(tienda.id),
                            title: Text(tienda.nombre),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _seleccionadas.add(tienda.id);
                              } else {
                                _seleccionadas.remove(tienda.id);
                              }
                            }),
                            secondary: IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: 'Editar, fusionar o cambiar de grupo',
                              onPressed: () => _editar(tienda, tiendas),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TransactionsList extends StatefulWidget {
  const _TransactionsList({
    required this.repository,
    required this.tipo,
    required this.onDelete,
    required this.onEdit,
  });

  final HouseholdRepository repository;
  final String tipo;
  final ValueChanged<TransactionSummary> onDelete;
  final ValueChanged<TransactionSummary> onEdit;

  @override
  State<_TransactionsList> createState() => _TransactionsListState();
}

class _TransactionsListState extends State<_TransactionsList> {
  // Igual que en _CategoriesTab: el stream se crea una sola vez, no en cada
  // build(), para no resuscribirse (y parpadear) sin necesidad. Cambiar de
  // mes solo cambia qué se filtra de lo que ya llega.
  late final _stream = widget.repository.watchTransactions(widget.tipo);

  /// Persona por la que se está filtrando; `null` es "todas".
  String? _persona;

  /// El mes contable que se está mirando, o nulo para el que corre ahora.
  /// Los pases de dinero no van por meses: una deuda no caduca con el mes.
  String? _mes;

  bool get _porMes => widget.tipo != 'liquidacion';

  final _searchController = TextEditingController();

  /// Lo escrito en el buscador. Mientras hay algo, se busca en todos los
  /// meses: lo normal es querer encontrar "cuándo pagué esto", y eso rara vez
  /// cae en el mes que se está mirando.
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Si [tx] encaja con [consulta], ya normalizada: por tienda, categoría,
  /// nota o quién pagó, sin distinguir tildes ni mayúsculas, o por importe
  /// ("12,5" encuentra 12,50 €).
  static bool _coincide(TransactionSummary tx, String consulta) {
    final textos = [tx.titulo, tx.comercio, tx.categoriaNombre, tx.nota, tx.pagadoPor, tx.de, tx.para];
    if (textos.any((t) => t != null && normalizeLine(t).contains(consulta))) return true;
    final importe = tx.importeTotal.toStringAsFixed(2);
    final consultaNumero = consulta.replaceAll(',', '.');
    return importe.contains(consultaNumero) || importe.replaceAll('.', ',').contains(consulta);
  }

  void _cambiarMes(String mesActual, int deltaMeses) {
    final primero = primerDiaDe(mesActual);
    setState(() => _mes = mesDe(DateTime(primero.year, primero.month + deltaMeses)));
  }

  @override
  Widget build(BuildContext context) {
    final esIngreso = widget.tipo == 'ingreso';
    final esPase = widget.tipo == 'liquidacion';
    return StreamBuilder(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final (:movimientos, :meses) = snapshot.data!;
        if (movimientos.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                switch (widget.tipo) {
                  'ingreso' => 'Todavía no has registrado ningún ingreso.\nPulsa el botón + para añadir uno.',
                  'liquidacion' => 'Todavía no os habéis pasado dinero.\nPulsa el botón + para apuntarlo.',
                  _ => 'Todavía no has registrado ningún gasto.\nPulsa el botón + para escanear un ticket o añadirlo a mano.',
                },
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
            ),
          );
        }

        // El mes no es el del calendario: lo que se gasta desde que entra la
        // nómina ya es del mes siguiente, igual que en el resumen.
        final mesAhora = meses.mesContableDe(DateTime.now());
        final mes = _mes ?? mesAhora;
        final consulta = normalizeLine(_query);
        final buscando = consulta.isNotEmpty;
        final porMes = _porMes && !buscando;
        final delMes = porMes
            ? movimientos.where((tx) => meses.mesContableDe(tx.fecha) == mes).toList()
            : movimientos;
        final encontrados = buscando ? delMes.where((tx) => _coincide(tx, consulta)).toList() : delMes;

        // "Ambos" es un valor de pagadoPor como otro cualquiera, así que va
        // como una opción más del filtro: filtrar por "Cano" enseña lo que
        // pagó él, no lo que pagaron entre los dos. En un pase, pagadoPor es
        // quien puso el dinero.
        final visibles =
            _persona == null ? encontrados : encontrados.where((tx) => tx.pagadoPor == _persona).toList();
        final total = visibles.fold<double>(0, (sum, tx) => sum + tx.importeTotal);
        final tramo = meses.tramoDe(mes);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: switch (widget.tipo) {
                    'ingreso' => 'Buscar ingreso',
                    'liquidacion' => 'Buscar pase de dinero',
                    _ => 'Buscar gasto',
                  },
                  hintText: 'Tienda, nota, importe...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: buscando
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Borrar búsqueda',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            if (porMes) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: MonthSelector(
                  etiqueta: etiquetaMes(primerDiaDe(mes)),
                  onAnterior: () => _cambiarMes(mes, -1),
                  onSiguiente: mes == mesAhora ? null : () => _cambiarMes(mes, 1),
                  onHoy: mes == mesAhora ? null : () => setState(() => _mes = null),
                ),
              ),
              TramoDelMes(
                desde: tramo.desde,
                hasta: tramo.hasta.subtract(const Duration(days: 1)),
                segunNomina: meses.segunNomina(mes),
              ),
            ],
            _PersonFilter(
              selected: _persona,
              onChanged: (persona) => setState(() => _persona = persona),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    [
                      '${visibles.length} ${_etiquetaCantidad(visibles.length)}',
                      if (buscando && _porMes) 'en todos los meses',
                    ].join(' '),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                  // Sumar pases que van en los dos sentidos no da nada que
                  // leer: lo que importa de ellos es el saldo, y está en el
                  // detalle de cada uno.
                  if (!esPase)
                    Text(
                      '${esIngreso ? '+' : '-'}${euros(total)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: esIngreso ? Colors.green : null,
                          ),
                    ),
                ],
              ),
            ),
            if (visibles.isEmpty)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _sinResultados(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                    ),
                  ),
                ),
              )
            else
              Expanded(child: _buildList(visibles, esIngreso)),
          ],
        );
      },
    );
  }

  String _etiquetaCantidad(int cuantos) => switch (widget.tipo) {
        'ingreso' => cuantos == 1 ? 'ingreso' : 'ingresos',
        'liquidacion' => cuantos == 1 ? 'pase de dinero' : 'pases de dinero',
        _ => cuantos == 1 ? 'gasto' : 'gastos',
      };

  String _sinResultados() {
    if (_query.trim().isNotEmpty) return 'Nada coincide con "${_query.trim()}".';
    final enElMes = _porMes ? ' este mes' : '';
    return switch ((widget.tipo, _persona)) {
      ('ingreso', null) => 'No hay ingresos$enElMes.',
      ('ingreso', final persona) => 'No hay ingresos de $persona$enElMes.',
      ('liquidacion', final persona) => 'No hay pases de dinero de $persona.',
      (_, null) => 'No hay gastos$enElMes.',
      (_, final persona) => 'No hay gastos pagados por $persona$enElMes.',
    };
  }

  Widget _buildList(List<TransactionSummary> transactions, bool esIngreso) {
    return ListView.builder(
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        final tx = transactions[index];
        final fechaTexto = '${tx.fecha.day}/${tx.fecha.month}/${tx.fecha.year}';
        final subtitulo = [
          fechaTexto,
          if (tx.esLiquidacion)
            '${tx.de} → ${tx.para}'
          else ...[
            if (tx.pagadoPor != null) tx.pagadoPor!,
            if (!tx.compartido) 'Personal',
          ],
          if (tx.nota != null) tx.nota!,
        ].join(' · ');
        return ListTile(
          title: Text(tx.titulo),
          subtitle: Text(subtitulo),
          // Una liquidación no se edita: son cuatro datos, si está mal se
          // borra y se vuelve a apuntar.
          onTap: tx.esLiquidacion ? null : () => widget.onEdit(tx),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                // Sin signo: no es dinero que salga de la casa, solo cambia
                // de bolsillo.
                '${tx.esLiquidacion ? '' : (esIngreso ? '+' : '-')}${euros(tx.importeTotal)}',
                style: TextStyle(
                  color: tx.esLiquidacion ? Colors.grey : (esIngreso ? Colors.green : null),
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: tx.esLiquidacion
                    ? 'Borrar movimiento'
                    : (esIngreso ? 'Borrar ingreso' : 'Borrar gasto'),
                onPressed: () => widget.onDelete(tx),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Filtro de "quién pagó" para las listas de gastos e ingresos.
class _PersonFilter extends StatelessWidget {
  const _PersonFilter({required this.selected, required this.onChanged});

  /// `null` = sin filtrar.
  final String? selected;
  final ValueChanged<String?> onChanged;

  static const _personas = ['Cano', 'Cana', 'Ambos'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Todos'),
            selected: selected == null,
            onSelected: (_) => onChanged(null),
          ),
          for (final persona in _personas)
            ChoiceChip(
              label: Text(persona),
              selected: selected == persona,
              // Volver a tocar la persona ya elegida quita el filtro, que es
              // lo que se espera al pulsar algo que ya está marcado.
              onSelected: (value) => onChanged(value ? persona : null),
            ),
        ],
      ),
    );
  }
}
