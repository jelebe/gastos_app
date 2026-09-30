/// Cómo van las cuentas entre los dos: quién ha puesto de más y cuánto le
/// debe el otro.
///
/// No se guarda en ninguna parte: se calcula cada vez a partir de los gastos
/// compartidos y de las liquidaciones ya hechas. Así un ticket corregido (o
/// borrado) se refleja solo, sin tener que tocar el saldo a mano.
class SettlementBalance {
  const SettlementBalance({
    required this.acreedor,
    required this.deudor,
    required this.importe,
    required this.gastosContados,
    this.ultimaLiquidacion,
  });

  /// Quien ha adelantado de más, y quien se lo debe.
  final String acreedor;
  final String deudor;

  /// Lo que [deudor] le debe a [acreedor]. Nunca es negativo: la dirección de
  /// la deuda va en quién es quién, no en el signo.
  final double importe;

  /// Cuántos gastos compartidos hay detrás de este saldo, para poder decir de
  /// dónde sale el número.
  final int gastosContados;

  /// Cuándo se saldó por última vez, si se ha hecho alguna vez.
  final DateTime? ultimaLiquidacion;

  /// Están en paz. Se compara contra medio céntimo porque el saldo sale de
  /// dividir importes por dos: un número de gastos impar deja restos de
  /// fracciones de céntimo que no son una deuda real.
  bool get saldado => importe < 0.005;
}
