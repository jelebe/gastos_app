import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/ticket_line_item.dart';
import '../models/transaction_summary.dart';
import '../services/household_repository.dart';
import '../widgets/add_income_sheet.dart';
import '../widgets/category_picker_sheet.dart';
import '../widgets/update_dialog.dart';
import 'capture_screen.dart';
import 'confirm_ticket_screen.dart';
import 'dashboard_tab.dart';

enum _Section { inicio, ingresos, gastos, categorias }

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
  }

  static const _titulos = {
    _Section.inicio: 'Inicio',
    _Section.ingresos: 'Ingresos',
    _Section.gastos: 'Gastos',
    _Section.categorias: 'Categorías',
  };

  /// Se cambia cada vez que se guarda o se borra algo, para que el dashboard
  /// (que carga sus datos una vez, no en vivo) los recalcule. Va como dato y
  /// no como `Key` a propósito: con una `Key` el widget se recreaba entero y
  /// perdía el mes que se estuviera mirando.
  int _dashboardTick = 0;

  void _refreshDashboard() => setState(() => _dashboardTick++);

  void _selectSection(_Section section) {
    Navigator.of(context).pop(); // cierra el drawer
    setState(() => _section = section);
  }

  Future<void> _showAddExpenseOptions(BuildContext context) async {
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
    }
    _refreshDashboard();
  }

  Future<void> _addIncome(BuildContext context) async {
    final categories = await _repository.loadCategories();
    if (!context.mounted) return;
    await showAddIncomeSheet(context, repository: _repository, categories: categories);
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
        title: Text(esIngreso ? 'Borrar ingreso' : 'Borrar gasto'),
        content: const Text('¿Seguro que quieres borrarlo? No se puede deshacer.'),
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
                icon: Icons.category_outlined,
                label: 'Categorías',
                selected: _section == _Section.categorias,
                onTap: () => _selectSection(_Section.categorias),
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
          _CategoriesTab(repository: _repository, onDeleteCategory: _confirmDeleteCategory),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => switch (_section) {
          _Section.ingresos => _addIncome(context),
          _Section.categorias => _addCategory(context),
          _Section.inicio || _Section.gastos => _showAddExpenseOptions(context),
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

enum _AddChoice { scan, manual }

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
  // build(), para no resuscribirse (y parpadear) sin necesidad.
  late final Stream<List<TransactionSummary>> _stream = widget.repository.watchTransactions(widget.tipo);

  /// Persona por la que se está filtrando; `null` es "todas".
  String? _persona;

  @override
  Widget build(BuildContext context) {
    final esIngreso = widget.tipo == 'ingreso';
    return StreamBuilder<List<TransactionSummary>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final transactions = snapshot.data!;
        if (transactions.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                esIngreso
                    ? 'Todavía no has registrado ningún ingreso.\nPulsa el botón + para añadir uno.'
                    : 'Todavía no has registrado ningún gasto.\nPulsa el botón + para escanear un ticket o añadirlo a mano.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
            ),
          );
        }

        // "Ambos" es un valor de pagadoPor como otro cualquiera, así que va
        // como una opción más del filtro: filtrar por "Cano" enseña lo que
        // pagó él, no lo que pagaron entre los dos.
        final visibles = _persona == null
            ? transactions
            : transactions.where((tx) => tx.pagadoPor == _persona).toList();
        final total = visibles.fold<double>(0, (sum, tx) => sum + tx.importeTotal);

        return Column(
          children: [
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
                    '${visibles.length} ${_etiquetaCantidad(visibles.length, esIngreso)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                  Text(
                    '${esIngreso ? '+' : '-'}${total.toStringAsFixed(2)} €',
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
                      esIngreso
                          ? 'No hay ingresos de $_persona.'
                          : 'No hay gastos pagados por $_persona.',
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

  String _etiquetaCantidad(int cuantos, bool esIngreso) {
    if (esIngreso) return cuantos == 1 ? 'ingreso' : 'ingresos';
    return cuantos == 1 ? 'gasto' : 'gastos';
  }

  Widget _buildList(List<TransactionSummary> transactions, bool esIngreso) {
    return ListView.builder(
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        final tx = transactions[index];
        final titulo = esIngreso
            ? (tx.categoriaNombre ?? 'Ingreso')
            : ((tx.comercio?.trim().isNotEmpty ?? false) ? tx.comercio!.trim() : 'Ticket');
        final fechaTexto = '${tx.fecha.day}/${tx.fecha.month}/${tx.fecha.year}';
        final subtitulo = [
          fechaTexto,
          if (tx.pagadoPor != null) tx.pagadoPor!,
          if (!tx.compartido) 'Personal',
          if (tx.nota != null) tx.nota!,
        ].join(' · ');
        return ListTile(
          title: Text(titulo),
          subtitle: Text(subtitulo),
          onTap: () => widget.onEdit(tx),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${esIngreso ? '+' : '-'}${tx.importeTotal.toStringAsFixed(2)} €',
                style: TextStyle(
                  color: esIngreso ? Colors.green : null,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: esIngreso ? 'Borrar ingreso' : 'Borrar gasto',
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
