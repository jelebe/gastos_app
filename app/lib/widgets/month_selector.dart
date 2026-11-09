import 'package:flutter/material.dart';

const _mutedInk = Color(0xFF898781);

const mesesCorto = [
  'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic', //
];

const mesesLargo = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', //
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre', //
];

/// "Septiembre 2026" a partir del primer día de ese mes.
String etiquetaMes(DateTime mes) => '${mesesLargo[mes.month - 1]} ${mes.year}';

/// Qué días entran en el mes que se está mirando.
///
/// Sale a la vista porque el mes arranca con la nómina y no el día 1, así que
/// sin decirlo los totales parecerían mal cuadrados. Si de ese mes no hay
/// nómina guardada se avisa de que el tramo es una estimación.
class TramoDelMes extends StatelessWidget {
  const TramoDelMes({super.key, required this.desde, required this.hasta, required this.segunNomina});

  final DateTime desde;

  /// El último día que entra, ya incluido.
  final DateTime hasta;
  final bool segunNomina;

  static String _dia(DateTime fecha) => '${fecha.day} ${mesesCorto[fecha.month - 1].toLowerCase()}';

  @override
  Widget build(BuildContext context) {
    return Text(
      [
        'Del ${_dia(desde)} al ${_dia(hasta)}',
        if (!segunNomina) 'estimado, sin nómina guardada',
      ].join(' · '),
      style: const TextStyle(color: _mutedInk, fontSize: 12),
    );
  }
}

/// Cabecera para moverse de mes en mes. La flecha de avanzar se apaga en el
/// mes en curso, y el propio nombre del mes devuelve a él de un toque.
class MonthSelector extends StatelessWidget {
  const MonthSelector({
    super.key,
    required this.etiqueta,
    required this.onAnterior,
    this.onSiguiente,
    this.onHoy,
  });

  final String etiqueta;
  final VoidCallback onAnterior;

  /// Nulos cuando ya se está en el mes en curso: ni se puede avanzar al
  /// futuro, ni tiene sentido ofrecer "volver a hoy".
  final VoidCallback? onSiguiente;
  final VoidCallback? onHoy;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Mes anterior',
          onPressed: onAnterior,
        ),
        InkWell(
          onTap: onHoy,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  etiqueta,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (onHoy != null)
                  const Text('Volver a este mes', style: TextStyle(color: _mutedInk, fontSize: 11)),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Mes siguiente',
          onPressed: onSiguiente,
        ),
      ],
    );
  }
}
