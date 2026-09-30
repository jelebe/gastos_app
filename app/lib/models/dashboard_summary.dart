/// Todo lo que la pantalla de inicio enseña de un mes.
///
/// Va junto en un único objeto porque se calcula de una sola pasada: los seis
/// bloques miran los mismos documentos, así que pedirlos por separado
/// significaba releer los tickets del mes una vez por bloque.
class DashboardSummary {
  DashboardSummary({
    required this.mes,
    required this.esMesEnCurso,
    required this.gastosPorMes,
    required this.ingresosPorMes,
    required this.categoryBreakdown,
    required this.categoryComparison,
    required this.personBreakdown,
    required this.personTotalSpending,
    required this.desde,
    required this.hasta,
    required this.inicioSegunNomina,
  });

  /// El mes contable que describe este resumen ("AAAA-MM").
  ///
  /// Lo decide el repositorio, no la pantalla: cuál es "el mes de ahora"
  /// depende de cuándo entró la última nómina, no del calendario.
  final String mes;

  /// Si [mes] es el mes contable en curso. Hoy puede ser 30 de septiembre y
  /// estar ya en el mes de octubre, porque la nómina entró el 29.
  final bool esMesEnCurso;

  /// Totales de los últimos meses, en orden cronológico y acabando en el mes
  /// que se está mirando. La clave de cada entrada es "AAAA-MM".
  final List<MapEntry<String, double>> gastosPorMes;
  final List<MapEntry<String, double>> ingresosPorMes;

  /// Gasto del mes por grupo de categoría, de mayor a menor.
  final List<MapEntry<String, double>> categoryBreakdown;

  /// El mismo gasto por grupo junto al del mes anterior, para la variación.
  final List<({String grupo, double actual, double anterior})> categoryComparison;

  /// Reparto del gasto compartido por quién lo pagó, de mayor a menor.
  final List<MapEntry<String, double>> personBreakdown;

  /// Lo que ha gastado cada uno en total, contando también lo personal y
  /// repartiendo al 50% lo pagado por "Ambos".
  final List<MapEntry<String, double>> personTotalSpending;

  /// El tramo de fechas que cubre el mes que se está mirando: de [desde]
  /// (incluido) a [hasta] (excluido).
  ///
  /// La pantalla lo enseña porque con la nómina a final de mes "octubre" no va
  /// del 1 al 31: empieza el día que entró la nómina que lo abre.
  final DateTime desde;
  final DateTime hasta;

  /// Si el mes arranca en una nómina guardada o en una estimación, porque de
  /// ese mes no hay ninguna. Se avisa: explica por qué el tramo no cuadra con
  /// el día de cobro.
  final bool inicioSegunNomina;

  /// El último día que entra en el mes, que es el anterior a [hasta] (que va
  /// excluido). Es lo que se enseña: un tramo "hasta el 24" se lee mejor que
  /// "hasta antes del 25".
  DateTime get ultimoDia => hasta.subtract(const Duration(days: 1));

  /// Los totales del mes que se está mirando: es el último de la serie, que
  /// acaba justo en él.
  double get gastoDelMes => gastosPorMes.isEmpty ? 0 : gastosPorMes.last.value;
  double get ingresoDelMes => ingresosPorMes.isEmpty ? 0 : ingresosPorMes.last.value;
  double get balance => ingresoDelMes - gastoDelMes;
}
