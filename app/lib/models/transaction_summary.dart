import 'package:cloud_firestore/cloud_firestore.dart';

/// El dinero se pasó para bajar una deuda que ya había.
const conceptoSaldar = 'saldar';

/// El dinero se pasó porque el otro lo necesitaba, así que crea deuda.
const conceptoPrestamo = 'prestamo';

/// Resumen de un gasto o ingreso ya guardado, para listarlo en las pestañas
/// de la pantalla principal. No incluye las líneas de un ticket (eso solo se
/// consulta al entrar en su detalle).
class TransactionSummary {
  TransactionSummary({
    required this.id,
    required this.tipo,
    required this.fecha,
    required this.importeTotal,
    this.comercio,
    this.categoriaId,
    this.categoriaNombre,
    this.nota,
    this.pagadoPor,
    this.compartido = true,
    this.de,
    this.para,
    this.concepto,
    this.aCuentaExterna = false,
  });

  factory TransactionSummary.fromFirestore(String id, Map<String, dynamic> data) {
    return TransactionSummary(
      id: id,
      tipo: data['tipo'] as String,
      fecha: (data['fecha'] as Timestamp).toDate(),
      importeTotal: (data['importeTotal'] as num).toDouble(),
      comercio: data['comercio'] as String?,
      categoriaId: data['categoriaId'] as String?,
      categoriaNombre: data['categoriaNombre'] as String?,
      nota: data['nota'] as String?,
      pagadoPor: data['pagadoPor'] as String?,
      // Los tickets guardados antes de que existiera este campo no lo tienen:
      // se tratan como compartidos (el valor por defecto), no como personales.
      compartido: data['compartido'] as bool? ?? true,
      de: data['de'] as String?,
      para: data['para'] as String?,
      concepto: data['concepto'] as String?,
      aCuentaExterna: data['aCuentaExterna'] == true,
    );
  }

  final String id;
  final String tipo;
  final DateTime fecha;
  final double importeTotal;
  final String? comercio;
  final String? categoriaId;
  final String? categoriaNombre;
  final String? nota;
  final String? pagadoPor;
  final bool compartido;

  /// En un movimiento de dinero entre los dos, de quién sale y a quién va.
  /// Solo ellos los tienen.
  final String? de;
  final String? para;

  /// Para qué se pasó el dinero: [conceptoSaldar] si bajaba una deuda o
  /// [conceptoPrestamo] si la creaba. Los movimientos guardados antes de que
  /// existiera este campo eran todos para saldar.
  final String? concepto;

  /// Si el dinero se pasó para ayudar al otro, no para saldar una deuda. Es lo
  /// mismo por dentro (mueve el saldo igual), pero se lee al revés.
  bool get esPrestamo => concepto == conceptoPrestamo;

  /// El dinero de este movimiento fue a una cuenta de fuera del circuito de
  /// ingresos y gastos de la casa (un ahorro que no se toca), en vez de a la
  /// cuenta del día a día.
  ///
  /// Va como marca de un movimiento entre los dos y no como un tipo aparte
  /// porque es una sola transferencia haciendo dos cosas: mover la deuda y
  /// sacar el dinero del disponible. Separarlo en dos apuntes invitaría a
  /// contarlo dos veces.
  final bool aCuentaExterna;

  /// El dinero ha salido del disponible: ni se ha gastado en nada ni deja de
  /// ser vuestro, pero ya no está para gastarlo este mes. Resta del disponible
  /// y no entra en el gasto por categoría.
  bool get saleDelDisponible => esLiquidacion && aCuentaExterna;

  /// Una devolución de dinero entre los dos: ni gasto ni ingreso de la casa,
  /// solo cambia de bolsillo. No suma en ningún total del resumen.
  bool get esLiquidacion => tipo == 'liquidacion';

  /// Con qué nombre se lista este movimiento.
  String get titulo {
    if (esLiquidacion) {
      final base = esPrestamo ? 'Dinero prestado' : 'Saldar deuda';
      return aCuentaExterna ? '$base (a cuenta externa)' : base;
    }
    if (tipo == 'ingreso') return categoriaNombre ?? 'Ingreso';
    return (comercio?.trim().isNotEmpty ?? false) ? comercio!.trim() : 'Ticket';
  }
}
