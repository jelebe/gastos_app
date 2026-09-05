import 'package:cloud_firestore/cloud_firestore.dart';

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
}
