import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/basket_inflation.dart';
import '../models/dashboard_summary.dart';
import '../models/product_summary.dart';
import '../models/ticket_line_item.dart';
import '../models/transaction_summary.dart';
import '../services/household_repository.dart';
import '../utils/formato.dart';
import '../widgets/month_selector.dart';

/// Paleta categórica de referencia (orden fijo, nunca se reordena ni se
/// genera un color nuevo para una serie de más: a partir de la 8ª se pliega
/// en "Otros").
const _categoricalPalette = [
  Color(0xFF2A78D6), // 1 azul
  Color(0xFFEB6834), // 2 naranja
  Color(0xFF1BAF7A), // 3 aguamarina
  Color(0xFFEDA100), // 4 amarillo
  Color(0xFFE87BA4), // 5 magenta
  Color(0xFF008300), // 6 verde
  Color(0xFF4A3AA7), // 7 violeta
  Color(0xFFE34948), // 8 rojo
];

const _successGreen = Color(0xFF006300);
const _statusCritical = Color(0xFFD03B3B);
const _mutedInk = Color(0xFF898781);
const _secondaryInk = Color(0xFF52514E);
const _gridline = Color(0xFFE1E0D9);

/// Resumen visual: KPIs del mes, gasto por categoría, evolución de los
/// últimos meses y los movimientos más recientes. Se puede mirar cualquier
/// mes pasado, no solo el que corre.
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key, required this.repository, required this.refreshTick});

  final HouseholdRepository repository;

  /// Cambia cada vez que se guarda o se borra algo fuera de esta pantalla.
  /// Se recargan los datos, pero sin rehacer el widget: así el mes que se
  /// está mirando no se pierde al volver de guardar un gasto.
  final int refreshTick;

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  /// El mes contable que se está mirando, o nulo para el que corre ahora.
  ///
  /// Nulo y no el mes del calendario: cuál es "el mes de ahora" depende de
  /// cuándo entró la última nómina, y eso solo lo sabe el repositorio. La
  /// pantalla lo recibe ya resuelto en [DashboardSummary.mes].
  String? _mes;
  late Future<DashboardSummary> _future = _load();

  Future<DashboardSummary> _load() => widget.repository.loadDashboardSummary(_mes);

  @override
  void didUpdateWidget(covariant DashboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) {
      setState(() {
        _future = _load();
      });
    }
  }

  void _volverAlMesEnCurso() {
    setState(() {
      _mes = null;
      _future = _load();
    });
  }

  /// Se mueve [deltaMeses] desde [mesActual], que viene del resumen ya
  /// cargado: mientras no lo esté, no hay flechas que pulsar.
  void _cambiarMes(String mesActual, int deltaMeses) {
    final primero = primerDiaDe(mesActual);
    setState(() {
      _mes = mesDe(DateTime(primero.year, primero.month + deltaMeses));
      _future = _load();
    });
  }

  Future<void> _refresh() async {
    final next = _load();
    // Con cuerpo de bloque, no con `=>`: una flecha devuelve el valor de la
    // asignación (el propio Future), y setState rechaza un callback que
    // devuelva un Future, así que el refresco no llegaba a repintar.
    setState(() {
      _future = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<DashboardSummary>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final mes = data.mes;
          final etiqueta = etiquetaMes(primerDiaDe(mes));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              MonthSelector(
                etiqueta: etiqueta,
                onAnterior: () => _cambiarMes(mes, -1),
                onSiguiente: data.esMesEnCurso ? null : () => _cambiarMes(mes, 1),
                onHoy: data.esMesEnCurso ? null : _volverAlMesEnCurso,
              ),
              TramoDelMes(
                desde: data.desde,
                hasta: data.ultimoDia,
                segunNomina: data.inicioSegunNomina,
              ),
              const SizedBox(height: 12),
              _KpiRow(gasto: data.gastoDelMes, ingreso: data.ingresoDelMes, disponible: data.disponible),
              // Solo cuando ha salido algo: una fila a cero sería ruido.
              if (data.salidaDelMes > 0.005) ...[
                const SizedBox(height: 8),
                _LineaSalida(importe: data.salidaDelMes),
              ],
              const SizedBox(height: 28),
              Text('Gasto por categoría', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Toca una categoría para ver qué se ha comprado en ella, o "Resto" para las que no caben.',
                style: TextStyle(color: _mutedInk, fontSize: 12),
              ),
              const SizedBox(height: 12),
              _CategoryBreakdown(
                entries: data.categoryBreakdown,
                onTapEntry: (grupo) => _showGroupDetail(context, widget.repository, mes, etiqueta, grupo),
                onTapResto: (plegadas) =>
                    _showRestoDetail(context, widget.repository, mes, etiqueta, plegadas),
              ),
              const SizedBox(height: 28),
              Text('Reparto del gasto compartido', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Solo cuenta el gasto compartido, no el personal.',
                style: TextStyle(color: _mutedInk, fontSize: 12),
              ),
              const SizedBox(height: 12),
              _CategoryBreakdown(
                entries: data.personBreakdown,
                onTapEntry: (persona) => _showPersonDetail(
                  context,
                  widget.repository,
                  mes,
                  etiqueta,
                  persona,
                  soloCompartido: true,
                ),
              ),
              const SizedBox(height: 28),
              Text('Total gastado por cada uno', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Todo lo que gasta cada uno, compartido y personal ("Ambos" se reparte al 50%).',
                style: TextStyle(color: _mutedInk, fontSize: 12),
              ),
              const SizedBox(height: 12),
              _CategoryBreakdown(
                entries: data.personTotalSpending,
                onTapEntry: (persona) => _showPersonDetail(
                  context,
                  widget.repository,
                  mes,
                  etiqueta,
                  persona,
                  soloCompartido: false,
                ),
              ),
              const SizedBox(height: 28),
              Text('Comparado con el mes anterior', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _CategoryComparison(entries: data.categoryComparison),
              const SizedBox(height: 28),
              Text('Evolución (6 meses)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _MonthlyTrendChart(gastos: data.gastosPorMes, ingresos: data.ingresosPorMes),
              const SizedBox(height: 28),
              Text('Precios de tu cesta', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Cuánto ha subido lo que compras, con tus propios tickets.',
                style: TextStyle(color: _mutedInk, fontSize: 12),
              ),
              const SizedBox(height: 8),
              // Se abre a petición y no se carga con la pantalla: necesita las
              // líneas de los tickets de seis meses, que es mucho más de lo que
              // cuesta el resto del resumen junto.
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.trending_up),
                  title: const Text('Ver cómo han cambiado tus precios'),
                  subtitle: const Text('Comparando los últimos 3 meses con los 3 anteriores'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showInflationDetail(context, widget.repository, mes),
                ),
              ),
              const SizedBox(height: 28),
              Text('Últimos movimientos', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _RecentMovements(repository: widget.repository),
            ],
          );
        },
      ),
    );
  }
}

/// Lo que este mes ha salido a cuentas de fuera.
///
/// Va en su propia línea y no como un cuarto KPI porque no es lo mismo que
/// gastar: el dinero sigue siendo vuestro, solo que ya no se puede gastar. Se
/// dice que está restado, que es la pregunta que surge al verlo.
class _LineaSalida extends StatelessWidget {
  const _LineaSalida({required this.importe});

  final double importe;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.savings_outlined, size: 16, color: _mutedInk),
        const SizedBox(width: 8),
        const Expanded(
          child: Text('Salió a cuenta externa', style: TextStyle(color: _secondaryInk, fontSize: 13)),
        ),
        Text(
          euros(importe),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(width: 6),
        const Text('ya restado', style: TextStyle(color: _mutedInk, fontSize: 11)),
      ],
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.gasto, required this.ingreso, required this.disponible});

  final double gasto;
  final double ingreso;
  final double disponible;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatTile(label: 'Ingresos este mes', value: ingreso, color: _successGreen)),
        const SizedBox(width: 10),
        Expanded(child: _StatTile(label: 'Gastos este mes', value: gasto, color: _categoricalPalette[7])),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Disponible',
            value: disponible,
            color: disponible >= 0 ? _successGreen : _categoricalPalette[7],
            signed: true,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.color, this.signed = false});

  final String label;
  final double value;
  final Color color;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final texto = euros(value, conSigno: signed);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(color: _mutedInk, fontSize: 12)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                texto,
                style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reparto del gasto del mes: una única barra apilada (parte-todo) más su
/// leyenda con importe y porcentaje directamente etiquetados.
///
/// Si se pasa [onTapEntry], cada fila de la leyenda se puede tocar para ver
/// el detalle de lo que hay detrás. El tramo "Resto" no lleva a un detalle
/// suyo, porque no es una categoría real: con [onTapResto] se abre la lista de
/// las que ha plegado.
class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.entries, this.onTapEntry, this.onTapResto});

  final List<MapEntry<String, double>> entries;
  final ValueChanged<String>? onTapEntry;

  /// Recibe las entradas que no han cabido en la barra, ya plegadas en
  /// "Resto", para poder enseñarlas aparte.
  final ValueChanged<List<MapEntry<String, double>>>? onTapResto;

  static const _maxSlots = 7;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Text('Todavía no hay gasto registrado este mes.', style: TextStyle(color: _mutedInk));
    }

    // "esAgregado" marca el tramo que agrupa a las categorías que no caben en
    // la barra. Va como bandera y no por su nombre: se llama "Resto" y no
    // "Otros" precisamente porque existe un grupo de categorías llamado
    // "Otros" de verdad, y confundirlos era fácil.
    final visibles = [
      for (final e in entries.take(_maxSlots)) (key: e.key, value: e.value, esAgregado: false),
    ];
    final plegadas = entries.skip(_maxSlots).toList();
    if (plegadas.isNotEmpty) {
      final restoTotal = plegadas.fold<double>(0, (sum, e) => sum + e.value);
      visibles.add((key: 'Resto', value: restoTotal, esAgregado: true));
    }
    final total = visibles.fold<double>(0, (sum, e) => sum + e.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 28,
            child: Row(
              children: [
                for (var i = 0; i < visibles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2), // hueco de superficie entre segmentos
                  Expanded(
                    flex: (visibles[i].value * 1000).round().clamp(1, 1 << 30),
                    child: Container(color: _colorFor(i)),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < visibles.length; i++)
          _LegendRow(
            color: _colorFor(i),
            label: visibles[i].key,
            value: visibles[i].value,
            porcentaje: total <= 0 ? 0 : visibles[i].value / total * 100,
            onTap: switch (visibles[i].esAgregado) {
              // El agregado abre la lista de lo que ha plegado, no un detalle
              // propio que no existe.
              true => onTapResto == null ? null : () => onTapResto!(plegadas),
              false => onTapEntry == null ? null : () => onTapEntry!(visibles[i].key),
            },
          ),
      ],
    );
  }

  Color _colorFor(int i) => i < _categoricalPalette.length ? _categoricalPalette[i] : _mutedInk;
}

/// Una fila de la leyenda: color, nombre, importe y porcentaje. Si se puede
/// abrir su detalle se marca con una flecha, para que se vea que hay algo
/// debajo y no parezca una etiqueta muerta.
class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
    required this.porcentaje,
    this.onTap,
  });

  final Color color;
  final String label;
  final double value;
  final double porcentaje;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fila = Padding(
      padding: EdgeInsets.symmetric(vertical: onTap == null ? 4 : 6),
      child: Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
          Text(
            '${euros(value)} · ${porcentaje.toStringAsFixed(0)}%',
            style: const TextStyle(color: _secondaryInk, fontWeight: FontWeight.w600),
          ),
          if (onTap != null) const Icon(Icons.chevron_right, size: 18, color: _mutedInk),
        ],
      ),
    );
    if (onTap == null) return fila;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(6), child: fila);
  }
}

/// Variación del gasto por categoría respecto al mes anterior, en %. Gastar
/// más se marca en rojo (empeora), gastar menos en verde (mejora); una
/// categoría sin gasto el mes anterior se marca como "Nuevo" en vez de un
/// porcentaje sin sentido (dividir por cero).
class _CategoryComparison extends StatelessWidget {
  const _CategoryComparison({required this.entries});

  final List<({String grupo, double actual, double anterior})> entries;

  @override
  Widget build(BuildContext context) {
    final visibles = entries.where((e) => e.actual > 0 || e.anterior > 0).toList();
    if (visibles.isEmpty) {
      return const Text('Todavía no hay suficiente gasto para comparar.', style: TextStyle(color: _mutedInk));
    }
    return Column(
      children: [
        for (final e in visibles)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(child: Text(e.grupo, overflow: TextOverflow.ellipsis)),
                Text(euros(e.actual), style: const TextStyle(color: _secondaryInk)),
                const SizedBox(width: 12),
                SizedBox(width: 56, child: _DeltaBadge(actual: e.actual, anterior: e.anterior)),
              ],
            ),
          ),
      ],
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({required this.actual, required this.anterior});

  final double actual;
  final double anterior;

  @override
  Widget build(BuildContext context) {
    if (anterior <= 0) {
      return const Text('Nuevo', textAlign: TextAlign.end, style: TextStyle(color: _mutedInk, fontSize: 12, fontWeight: FontWeight.w600));
    }
    final delta = (actual - anterior) / anterior * 100;
    // Un margen de 0.5% evita marcar como "cambio" el ruido de céntimos.
    final sube = delta > 0.5;
    final baja = delta < -0.5;
    final color = sube ? _statusCritical : (baja ? _successGreen : _mutedInk);
    final icono = sube ? Icons.arrow_upward : (baja ? Icons.arrow_downward : Icons.remove);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 14, color: color),
        const SizedBox(width: 2),
        Text('${delta.abs().toStringAsFixed(0)}%', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}

class _MonthlyTrendChart extends StatelessWidget {
  const _MonthlyTrendChart({required this.gastos, required this.ingresos});

  final List<MapEntry<String, double>> gastos;
  final List<MapEntry<String, double>> ingresos;

  @override
  Widget build(BuildContext context) {
    final maxY = [...gastos, ...ingresos].map((e) => e.value).fold<double>(0, (m, v) => v > m ? v : m);
    final techo = maxY <= 0 ? 10.0 : maxY * 1.2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              maxY: techo,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: techo / 4,
                getDrawingHorizontalLine: (_) => const FlLine(color: _gridline, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= gastos.length) return const SizedBox.shrink();
                      final mes = int.parse(gastos[i].key.split('-')[1]);
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(mesesCorto[mes - 1], style: const TextStyle(color: _mutedInk, fontSize: 11)),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                    euros(rod.toY),
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < gastos.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: i < ingresos.length ? ingresos[i].value : 0,
                        color: _categoricalPalette[0],
                        width: 8,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      BarChartRodData(
                        toY: gastos[i].value,
                        color: _categoricalPalette[1],
                        width: 8,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendDot(color: _categoricalPalette[0], label: 'Ingresos'),
            const SizedBox(width: 16),
            _LegendDot(color: _categoricalPalette[1], label: 'Gastos'),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: _secondaryInk, fontSize: 12)),
      ],
    );
  }
}

class _RecentMovements extends StatefulWidget {
  const _RecentMovements({required this.repository});

  final HouseholdRepository repository;

  @override
  State<_RecentMovements> createState() => _RecentMovementsState();
}

class _RecentMovementsState extends State<_RecentMovements> {
  // El stream se crea una sola vez: si se creara dentro de build(), cada
  // rebuild de esta pantalla (p.ej. al hacer pull-to-refresh) haría que
  // StreamBuilder se resuscribiera de golpe a un stream "nuevo".
  late final Stream<List<TransactionSummary>> _stream = widget.repository.watchRecentTransactions();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TransactionSummary>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final movimientos = snapshot.data!;
        if (movimientos.isEmpty) {
          return const Text('Todavía no hay movimientos registrados.', style: TextStyle(color: _mutedInk));
        }
        return Column(
          children: [
            for (final m in movimientos)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                onTap: () => _showMovementDetail(context, widget.repository, m),
                title: Text(m.titulo),
                subtitle: Text(
                  [
                    '${m.fecha.day}/${m.fecha.month}/${m.fecha.year}',
                    if (m.esLiquidacion) '${m.de} → ${m.para}',
                  ].join(' · '),
                ),
                trailing: Text(
                  // Una liquidación va sin signo: no suma ni resta al gasto
                  // del mes, solo cambia el dinero de bolsillo.
                  '${m.esLiquidacion ? '' : (m.tipo == 'ingreso' ? '+' : '-')}${euros(m.importeTotal)}',
                  style: TextStyle(
                    color: m.esLiquidacion
                        ? _mutedInk
                        : (m.tipo == 'ingreso' ? _successGreen : null),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Ventana con el desglose de un movimiento: las líneas del ticket si es un
/// gasto, o la categoría y la nota si es un ingreso.
Future<void> _showMovementDetail(BuildContext context, HouseholdRepository repository, TransactionSummary tx) async {
  final esIngreso = tx.tipo == 'ingreso';
  // Solo los tickets tienen líneas: ni un ingreso ni una liquidación las
  // tienen, así que ni se piden.
  final tieneLineas = !esIngreso && !tx.esLiquidacion;
  List<TicketLineItem>? items;
  if (tieneLineas) {
    final categories = await repository.loadCategories();
    items = await repository.loadTicketItems(tx.id, categories);
  }
  if (!context.mounted) return;

  final titulo = tx.titulo;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          controller: scrollController,
          children: [
            Text(titulo, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              [
                '${tx.fecha.day}/${tx.fecha.month}/${tx.fecha.year}',
                if (tx.esLiquidacion)
                  tx.esPrestamo
                      ? '${tx.de} le dio el dinero a ${tx.para}'
                      : '${tx.de} le devolvió el dinero a ${tx.para}'
                else ...[
                  if (tx.pagadoPor != null) 'Pagado por ${tx.pagadoPor}',
                  if (!tx.compartido) 'Personal (no cuenta en el reparto)',
                ],
              ].join(' · '),
              style: const TextStyle(color: _mutedInk),
            ),
            if (tx.saleDelDisponible) ...[
              const SizedBox(height: 8),
              const Text(
                'Fue a una cuenta de fuera: mueve la deuda y además resta del disponible '
                'del mes, porque ese dinero ya no se puede gastar.',
                style: TextStyle(color: _mutedInk, fontSize: 12),
              ),
            ] else if (tx.esLiquidacion) ...[
              const SizedBox(height: 8),
              Text(
                tx.esPrestamo
                    ? 'No cuenta como gasto ni como ingreso: solo sube la deuda entre los dos.'
                    : 'No cuenta como gasto ni como ingreso: solo baja la deuda entre los dos.',
                style: const TextStyle(color: _mutedInk, fontSize: 12),
              ),
            ],
            if (tx.nota != null) ...[
              const SizedBox(height: 8),
              Text(tx.nota!),
            ],
            const SizedBox(height: 16),
            const Divider(),
            if (tieneLineas)
              if (items == null || items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No se han encontrado líneas para este ticket.', style: TextStyle(color: _mutedInk)),
                )
              else
                for (final item in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(item.textoOriginal),
                    subtitle: Text(item.productoNormalizado ?? 'Sin categoría'),
                    trailing: Text(
                      [
                        if (item.precioTotal != null) euros(item.precioTotal!),
                        if (item.pesoGramos != null) pesoLegible(item.pesoGramos!),
                      ].join('\n'),
                      textAlign: TextAlign.end,
                    ),
                  ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tx.esLiquidacion ? 'Devuelto' : 'Total',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${esIngreso ? '+' : ''}${euros(tx.importeTotal)}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: esIngreso ? _successGreen : null),
                ),
              ],
            ),
            if (tx.esLiquidacion) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _borrarLiquidacion(context, repository, tx),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Borrar movimiento'),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Borra una liquidación apuntada por error, sin tener que ir a buscarla a la
/// lista de pases de dinero.
Future<void> _borrarLiquidacion(
  BuildContext context,
  HouseholdRepository repository,
  TransactionSummary tx,
) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Borrar movimiento'),
      content: Text(
        tx.esPrestamo
            ? 'La deuda bajará ${euros(tx.importeTotal)}. No se puede deshacer.'
            : 'La deuda volverá a subir ${euros(tx.importeTotal)}. No se puede deshacer.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
        FilledButton.tonal(onPressed: () => Navigator.of(context).pop(true), child: const Text('Borrar')),
      ],
    ),
  );
  if (confirmado != true || !context.mounted) return;

  try {
    await repository.deleteTransaction(tx.id);
    if (context.mounted) Navigator.of(context).pop(); // cierra el detalle
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se ha podido borrar: $e')));
    }
  }
}

/// Cabecera común de las hojas de detalle: título, una línea de contexto y el
/// total de lo que se está listando.
class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.titulo, required this.contexto, required this.total});

  final String titulo;
  final String contexto;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(contexto, style: const TextStyle(color: _mutedInk)),
        const SizedBox(height: 12),
        Text(
          euros(total),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Divider(),
      ],
    );
  }
}

/// Las categorías que no han cabido en la barra, de mayor a menor. Cada una
/// abre su propio detalle, así que "Resto" deja de ser un callejón sin salida.
Future<void> _showRestoDetail(
  BuildContext context,
  HouseholdRepository repository,
  String mes,
  String mesEtiqueta,
  List<MapEntry<String, double>> plegadas,
) async {
  final total = plegadas.fold<double>(0, (sum, e) => sum + e.value);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          controller: scrollController,
          children: [
            _DetailHeader(
              titulo: 'Resto de categorías',
              contexto: '${plegadas.length} categorías en $mesEtiqueta',
              total: total,
            ),
            for (final entrada in plegadas)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(entrada.key),
                subtitle: Text(
                  total <= 0 ? '' : '${(entrada.value / total * 100).toStringAsFixed(0)}% del resto',
                  style: const TextStyle(color: _mutedInk),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(euros(entrada.value), style: const TextStyle(fontWeight: FontWeight.w600)),
                    const Icon(Icons.chevron_right, size: 20, color: _mutedInk),
                  ],
                ),
                onTap: () => _showGroupDetail(context, repository, mes, mesEtiqueta, entrada.key),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Qué se ha comprado de un grupo en el mes, agrupado por producto y de mayor
/// a menor gasto. Cada producto abre su ficha.
Future<void> _showGroupDetail(
  BuildContext context,
  HouseholdRepository repository,
  String mes,
  String mesEtiqueta,
  String grupo,
) async {
  final lineas = await repository.loadGroupLines(mes, grupo);
  if (!context.mounted) return;

  // Se agrupa por categoría y no por el nombre del producto: dos categorías
  // pueden llamarse igual, y las líneas de una categoría borrada se quedan sin
  // ella, así que caen todas juntas en un montón aparte que no se puede abrir.
  final porProducto = <String?, ({String nombre, double total, int compras})>{};
  for (final linea in lineas) {
    final actual = porProducto[linea.categoriaId];
    porProducto[linea.categoriaId] = (
      nombre: actual?.nombre ?? linea.producto ?? 'Sin categoría',
      total: (actual?.total ?? 0) + linea.precio,
      compras: (actual?.compras ?? 0) + 1,
    );
  }
  final productos = porProducto.entries.toList()..sort((a, b) => b.value.total.compareTo(a.value.total));
  final total = lineas.fold<double>(0, (sum, l) => sum + l.precio);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          controller: scrollController,
          children: [
            _DetailHeader(
              titulo: grupo,
              contexto: [
                '${productos.length} ${productos.length == 1 ? 'producto' : 'productos'}',
                '${lineas.length} ${lineas.length == 1 ? 'compra' : 'compras'} en $mesEtiqueta',
              ].join(' · '),
              total: total,
            ),
            if (productos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No hay gasto de este grupo en este mes.', style: TextStyle(color: _mutedInk)),
              )
            else
              for (final MapEntry(key: categoriaId, value: producto) in productos)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(producto.nombre),
                  subtitle: Text(
                    '${producto.compras} ${producto.compras == 1 ? 'compra' : 'compras'}',
                    style: const TextStyle(color: _mutedInk),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        euros(producto.total),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      // Lo que se quedó sin categoría no tiene ficha que abrir.
                      if (categoriaId != null)
                        const Icon(Icons.chevron_right, size: 20, color: _mutedInk)
                      else
                        const SizedBox(width: 20),
                    ],
                  ),
                  onTap: categoriaId == null
                      ? null
                      : () => _showProductDetail(context, repository, mes, categoriaId),
                ),
          ],
        ),
      ),
    ),
  );
}

/// Cuánto ha subido el precio de lo que se compra, producto a producto.
Future<void> _showInflationDetail(
  BuildContext context,
  HouseholdRepository repository,
  String mes,
) async {
  final datos = await repository.loadBasketInflation(mes);
  if (!context.mounted) return;

  String tramo(List<String> meses) => meses.isEmpty
      ? '—'
      : '${_mesCortoDeClave(meses.first)}–${_mesCortoDeClave(meses.last)}';

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          controller: scrollController,
          children: [
            Text('Precios de tu cesta', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${tramo(datos.mesesAhora)} comparado con ${tramo(datos.mesesAntes)}',
              style: const TextStyle(color: _mutedInk),
            ),
            const SizedBox(height: 12),
            if (!datos.hayDatos)
              const Text(
                'Todavía no hay con qué comparar. Hace falta el mismo producto comprado al peso '
                'en los dos tramos: con unas semanas más de tickets empieza a salir.',
                style: TextStyle(color: _mutedInk),
              )
            else ...[
              Text(
                '${datos.variacion! >= 0 ? '+' : ''}${numeroEs(datos.variacion! * 100, decimales: 1)} %',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: datos.variacion! > 0 ? _statusCritical : _successGreen,
                ),
              ),
              Text(
                'sobre ${datos.cambios.length} ${datos.cambios.length == 1 ? 'producto' : 'productos'} comparables'
                '${datos.productosDescartados > 0 ? ' · ${datos.productosDescartados} sin precio en los dos tramos' : ''}',
                style: const TextStyle(color: _mutedInk, fontSize: 12),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pesa cada producto por lo que gastas en él ahora: que suba el aceite importa '
                'más que el perejil.',
                style: TextStyle(color: _mutedInk, fontSize: 12),
              ),
              const SizedBox(height: 16),
              const Divider(),
              if (datos.subidas.isNotEmpty) ...[
                Text('Lo que más ha subido', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final cambio in datos.subidas) _CambioDePrecio(cambio: cambio),
                const SizedBox(height: 16),
              ],
              if (datos.bajadas.isNotEmpty) ...[
                Text('Lo que ha bajado', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final cambio in datos.bajadas) _CambioDePrecio(cambio: cambio),
              ],
            ],
          ],
        ),
      ),
    ),
  );
}

/// Un producto con su precio antes y ahora.
class _CambioDePrecio extends StatelessWidget {
  const _CambioDePrecio({required this.cambio});

  final ProductPriceChange cambio;

  @override
  Widget build(BuildContext context) {
    final sube = cambio.variacion > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(cambio.producto, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text(
            '${numeroEs(cambio.precioAntes)} → ${numeroEs(cambio.precioAhora)} €/kg',
            style: const TextStyle(color: _mutedInk, fontSize: 12),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 56,
            child: Text(
              '${sube ? '+' : ''}${numeroEs(cambio.variacion * 100, decimales: 0)} %',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: sube ? _statusCritical : _successGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La ficha de un producto: lo que cuesta, cómo ha ido en los últimos meses y
/// en qué compras.
Future<void> _showProductDetail(
  BuildContext context,
  HouseholdRepository repository,
  String mes,
  String categoriaId,
) async {
  final ficha = await repository.loadProductSummary(categoriaId, mes);
  if (!context.mounted) return;

  // Se abre desde un mes, así que lo de arriba y la lista son de ese mes. Lo
  // demás (precios, tiendas, evolución) mira la ventana entera: con las
  // compras de un solo mes no hay con qué comparar.
  final mesEtiqueta = etiquetaMes(primerDiaDe(mes));
  final delMes = ficha.lineasDelMes;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          controller: scrollController,
          children: [
            _DetailHeader(
              titulo: ficha.producto,
              contexto: [
                if (ficha.grupo != null) ficha.grupo!,
                '${delMes.length} ${delMes.length == 1 ? 'compra' : 'compras'} en $mesEtiqueta',
              ].join(' · '),
              total: ficha.totalDelMes,
            ),
            Text('Últimos ${ficha.porMes.length} meses', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            _FichaDato(
              etiqueta: 'Gastado',
              valor: euros(ficha.total),
              detalle: '${ficha.compras} ${ficha.compras == 1 ? 'compra' : 'compras'}',
            ),
            if (ficha.pesoTotalGramos case final peso?)
              _FichaDato(
                etiqueta: 'Comprado',
                valor: pesoLegible(peso),
              ),
            if (ficha.precioMedioPorKilo case final medio?)
              _FichaDato(etiqueta: 'Precio medio', valor: '${numeroEs(medio)} €/kg'),
            if (ficha.masBarato case final barato?)
              _FichaDato(
                etiqueta: 'Más barato',
                valor: '${numeroEs(barato.precioPorKilo)} €/kg',
                detalle: [
                  if (barato.comercio?.trim().isNotEmpty ?? false) barato.comercio!.trim(),
                  '${barato.fecha.day}/${barato.fecha.month}',
                ].join(', '),
              ),
            if (ficha.sePuedeCompararTiendas) ...[
              const SizedBox(height: 20),
              Text('Dónde sale más barato', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text(
                'Precio medio por kilo en cada tienda, solo de lo comprado al peso.',
                style: TextStyle(color: _mutedInk, fontSize: 12),
              ),
              const SizedBox(height: 8),
              _PreciosPorTienda(precios: ficha.porComercio, ahorro: ficha.ahorroPosible),
            ],
            const SizedBox(height: 20),
            Text('Evolución', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            _ProductTrend(porMes: ficha.porMes),
            const SizedBox(height: 20),
            const Divider(),
            Text('Compras en $mesEtiqueta', style: Theme.of(context).textTheme.titleSmall),
            if (delMes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('No se ha comprado en $mesEtiqueta.', style: const TextStyle(color: _mutedInk)),
              )
            else
              for (final compra in delMes)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    [
                      '${compra.fecha.day}/${compra.fecha.month}/${compra.fecha.year}',
                      if (compra.comercio?.trim().isNotEmpty ?? false) compra.comercio!.trim(),
                    ].join(' · '),
                  ),
                  subtitle: Text(
                    [
                      if (compra.pesoGramos != null) pesoLegible(compra.pesoGramos!),
                      if (compra.precioPorKilo != null) '${numeroEs(compra.precioPorKilo!)} €/kg',
                      if (compra.pagadoPor != null) compra.pagadoPor!,
                      if (!compra.compartido) 'Personal',
                    ].join(' · '),
                    style: const TextStyle(color: _mutedInk),
                  ),
                  trailing: Text(
                    euros(compra.precio),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}

/// Lo que cuesta un producto en cada tienda, de la más barata a la más cara,
/// y lo que se habría ahorrado comprando siempre en la primera.
class _PreciosPorTienda extends StatelessWidget {
  const _PreciosPorTienda({required this.precios, required this.ahorro});

  final List<StorePrice> precios;
  final double? ahorro;

  @override
  Widget build(BuildContext context) {
    final masCaro = precios.last.precioPorKilo;
    final masBarato = precios.first.precioPorKilo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final precio in precios)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    precio.comercio,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: precio.precioPorKilo == masBarato ? FontWeight.bold : null,
                    ),
                  ),
                ),
                Text(
                  '${precio.compras} ${precio.compras == 1 ? 'compra' : 'compras'}',
                  style: const TextStyle(color: _mutedInk, fontSize: 12),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 78,
                  child: Text(
                    '${numeroEs(precio.precioPorKilo)} €/kg',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      // Verde la más barata y rojo la más cara solo si de
                      // verdad se diferencian: con dos tiendas al mismo precio,
                      // pintar una de cada color sería inventar una diferencia.
                      color: masCaro == masBarato
                          ? null
                          : precio.precioPorKilo == masBarato
                              ? _successGreen
                              : precio.precioPorKilo == masCaro
                                  ? _statusCritical
                                  : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (ahorro != null && ahorro! > 0.005) ...[
          const SizedBox(height: 6),
          Text(
            'Comprando siempre en ${precios.first.comercio} te habrías ahorrado ${euros(ahorro!)}.',
            style: const TextStyle(color: _secondaryInk, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// Una fila de dato de la ficha: etiqueta a la izquierda, valor a la derecha.
class _FichaDato extends StatelessWidget {
  const _FichaDato({required this.etiqueta, required this.valor, this.detalle});

  final String etiqueta;
  final String valor;

  /// Aclaración que acompaña al valor, más discreta (dónde, cuándo...).
  final String? detalle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(etiqueta, style: const TextStyle(color: _secondaryInk))),
          Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (detalle != null) ...[
            const SizedBox(width: 6),
            Text(detalle!, style: const TextStyle(color: _mutedInk, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

/// Lo gastado en un producto mes a mes, en barras.
///
/// Las barras van en proporción al mes que más, no a una escala absoluta: lo
/// que interesa es si sube o baja, no cuánto pesa dentro del gasto total.
class _ProductTrend extends StatelessWidget {
  const _ProductTrend({required this.porMes});

  final List<MapEntry<String, double>> porMes;

  static const _alturaMaxima = 56.0;

  @override
  Widget build(BuildContext context) {
    final maximo = porMes.fold<double>(0, (mayor, e) => e.value > mayor ? e.value : mayor);
    if (maximo <= 0) {
      return const Text('Sin compras en estos meses.', style: TextStyle(color: _mutedInk));
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final entrada in porMes)
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entrada.value <= 0 ? '—' : numeroEs(entrada.value, decimales: 0),
                  style: const TextStyle(color: _secondaryInk, fontSize: 10),
                ),
                const SizedBox(height: 4),
                Container(
                  // Un suelo de 3 px para que un mes de poco gasto se vea, en
                  // vez de quedarse en una línea invisible.
                  height: 3 + _alturaMaxima * entrada.value / maximo,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: entrada.value <= 0 ? _gridline : _categoricalPalette.first,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(_mesCortoDeClave(entrada.key), style: const TextStyle(color: _mutedInk, fontSize: 10)),
              ],
            ),
          ),
      ],
    );
  }
}

/// "oct" a partir de una clave "AAAA-MM".
String _mesCortoDeClave(String mes) => mesesCorto[primerDiaDe(mes).month - 1].toLowerCase();

/// Detalle del gasto de una persona en el mes. Con [soloCompartido] se listan
/// solo los tickets compartidos que pagó ella (lo que se reparte); sin él, se
/// lista todo lo que le toca, incluidos los tickets pagados por "Ambos", que
/// cuentan a la mitad.
Future<void> _showPersonDetail(
  BuildContext context,
  HouseholdRepository repository,
  String mes,
  String mesEtiqueta,
  String persona, {
  required bool soloCompartido,
}) async {
  final gastos = await repository.loadMonthExpenses(mes);
  if (!context.mounted) return;

  bool esDeLaPersona(TransactionSummary tx) =>
      tx.pagadoPor == persona || (persona == 'Sin especificar' && tx.pagadoPor == null);

  final visibles = gastos.where((tx) {
    if (soloCompartido) return tx.compartido && esDeLaPersona(tx);
    return esDeLaPersona(tx) || tx.pagadoPor == 'Ambos';
  }).toList();

  // Un ticket de "Ambos" solo aporta la mitad al total de cada uno, igual que
  // en el gráfico del que se ha abierto este detalle.
  double importeImputado(TransactionSummary tx) =>
      (!soloCompartido && tx.pagadoPor == 'Ambos' && persona != 'Ambos')
          ? tx.importeTotal / 2
          : tx.importeTotal;

  final total = visibles.fold<double>(0, (sum, tx) => sum + importeImputado(tx));

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          controller: scrollController,
          children: [
            _DetailHeader(
              titulo: persona,
              contexto: soloCompartido
                  ? '${visibles.length} ${visibles.length == 1 ? 'gasto compartido' : 'gastos compartidos'} en $mesEtiqueta'
                  : '${visibles.length} ${visibles.length == 1 ? 'gasto' : 'gastos'} en $mesEtiqueta (compartidos y personales)',
              total: total,
            ),
            if (visibles.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No hay gastos de esta persona en este mes.', style: TextStyle(color: _mutedInk)),
              )
            else
              for (final tx in visibles)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text((tx.comercio?.trim().isNotEmpty ?? false) ? tx.comercio!.trim() : 'Ticket'),
                  subtitle: Text(
                    [
                      '${tx.fecha.day}/${tx.fecha.month}/${tx.fecha.year}',
                      if (importeImputado(tx) != tx.importeTotal) 'Ambos · 50% de ${euros(tx.importeTotal)}',
                      if (!tx.compartido) 'Personal',
                      if (tx.nota != null) tx.nota!,
                    ].join(' · '),
                  ),
                  trailing: Text(
                    euros(importeImputado(tx)),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}
