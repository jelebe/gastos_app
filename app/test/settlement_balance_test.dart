import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_app/services/household_repository.dart';

MovimientoSaldo gasto(String? quienPaga, double importe, {bool compartido = true}) =>
    (tipo: 'gasto', quienPaga: quienPaga, importe: importe, compartido: compartido, fecha: DateTime(2026, 9, 1));

MovimientoSaldo liquidacion(String de, double importe, {DateTime? fecha}) =>
    (tipo: 'liquidacion', quienPaga: de, importe: importe, compartido: true, fecha: fecha ?? DateTime(2026, 9, 10));

void main() {
  group('balanceDe', () {
    test('sin movimientos, en paz', () {
      final saldo = balanceDe([]);
      expect(saldo.saldado, isTrue);
      expect(saldo.gastosContados, 0);
      expect(saldo.ultimaLiquidacion, isNull);
    });

    test('quien paga un gasto compartido queda a favor de la mitad', () {
      final saldo = balanceDe([gasto(personaA, 100)]);
      expect(saldo.acreedor, personaA);
      expect(saldo.deudor, personaB);
      expect(saldo.importe, 50);
      expect(saldo.gastosContados, 1);
    });

    test('los gastos de los dos se compensan entre sí', () {
      final saldo = balanceDe([gasto(personaA, 100), gasto(personaB, 60)]);
      expect(saldo.acreedor, personaA);
      expect(saldo.importe, closeTo(20, 0.001)); // 50 - 30
    });

    test('un gasto personal no mueve el saldo', () {
      final saldo = balanceDe([gasto(personaA, 100, compartido: false)]);
      expect(saldo.saldado, isTrue);
      expect(saldo.gastosContados, 0);
    });

    test('lo pagado por Ambos ya iba a medias, no mueve el saldo', () {
      final saldo = balanceDe([gasto(pagadoPorAmbos, 100)]);
      expect(saldo.saldado, isTrue);
    });

    test('saldar la deuda entera deja las cuentas a cero', () {
      final saldo = balanceDe([gasto(personaA, 100), liquidacion(personaB, 50)]);
      expect(saldo.saldado, isTrue);
      expect(saldo.ultimaLiquidacion, DateTime(2026, 9, 10));
    });

    test('una devolución parcial deja el resto pendiente', () {
      final saldo = balanceDe([gasto(personaA, 200), liquidacion(personaB, 60)]);
      expect(saldo.acreedor, personaA);
      expect(saldo.deudor, personaB);
      expect(saldo.importe, closeTo(40, 0.001)); // 100 - 60
    });

    test('devolver de más le da la vuelta a la deuda', () {
      final saldo = balanceDe([gasto(personaA, 100), liquidacion(personaB, 80)]);
      expect(saldo.acreedor, personaB);
      expect(saldo.deudor, personaA);
      expect(saldo.importe, closeTo(30, 0.001)); // 80 - 50
    });

    test('la última liquidación es la más reciente, no la última leída', () {
      final saldo = balanceDe([
        liquidacion(personaB, 10, fecha: DateTime(2026, 8, 3)),
        liquidacion(personaB, 10, fecha: DateTime(2026, 9, 12)),
        liquidacion(personaA, 20, fecha: DateTime(2026, 7, 1)),
      ]);
      expect(saldo.ultimaLiquidacion, DateTime(2026, 9, 12));
    });

    test('un movimiento sin quién pagó se ignora', () {
      final saldo = balanceDe([gasto(null, 100)]);
      expect(saldo.saldado, isTrue);
      expect(saldo.gastosContados, 0);
    });

    test('un número impar de gastos no deja una deuda de céntimos falsa', () {
      // Tres gastos de 10 € pagados uno por cada lado y el tercero a medias:
      // 5 - 5 = 0, aunque la división por dos deje restos binarios.
      final saldo = balanceDe([gasto(personaA, 10.01), gasto(personaB, 10.01), gasto(pagadoPorAmbos, 10.01)]);
      expect(saldo.saldado, isTrue);
    });
  });
}
