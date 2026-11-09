import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_app/services/household_repository.dart';

void main() {
  group('esNominaCategoria', () {
    test('reconoce la nómina con y sin tilde, y con apellido', () {
      expect(esNominaCategoria('Nómina'), isTrue);
      expect(esNominaCategoria('nomina'), isTrue);
      expect(esNominaCategoria('Nómina de Cana'), isTrue);
    });

    test('el resto de ingresos no abren mes', () {
      expect(esNominaCategoria('Ingresos freelance'), isFalse);
      expect(esNominaCategoria('Reembolsos'), isFalse);
      expect(esNominaCategoria(null), isFalse);
    });
  });

  group('mesQueAbreLaNomina', () {
    test('cobrada a final de mes, abre el mes siguiente', () {
      expect(mesQueAbreLaNomina(DateTime(2026, 9, 29)), '2026-10');
      expect(mesQueAbreLaNomina(DateTime(2026, 9, 15)), '2026-10');
    });

    test('cobrada con retraso, ya entrado el mes, abre ese mismo mes', () {
      expect(mesQueAbreLaNomina(DateTime(2026, 10, 2)), '2026-10');
      expect(mesQueAbreLaNomina(DateTime(2026, 10, 14)), '2026-10');
    });

    test('la de diciembre abre enero del año siguiente', () {
      expect(mesQueAbreLaNomina(DateTime(2026, 12, 31)), '2027-01');
    });
  });

  group('MesesContables', () {
    test('el caso que lo motiva: nómina el 29/09, gasto el 30/09 es de octubre', () {
      final meses = MesesContables.deNominas([DateTime(2026, 9, 29)]);
      expect(meses.mesContableDe(DateTime(2026, 9, 29)), '2026-10');
      expect(meses.mesContableDe(DateTime(2026, 9, 30)), '2026-10');
      expect(meses.mesContableDe(DateTime(2026, 9, 28)), '2026-09');
    });

    test('si los dos cobran, el mes arranca con la primera de las dos', () {
      final meses = MesesContables.deNominas([DateTime(2026, 9, 30), DateTime(2026, 9, 29)]);
      expect(meses.inicioDe('2026-10'), DateTime(2026, 9, 29));
      expect(meses.mesContableDe(DateTime(2026, 9, 29)), '2026-10');
    });

    test('de la nómina se toma el día, no la hora', () {
      final meses = MesesContables.deNominas([DateTime(2026, 9, 29, 14, 30)]);
      expect(meses.inicioDe('2026-10'), DateTime(2026, 9, 29));
      // Una compra esa misma mañana, antes de que constara el ingreso, entra.
      expect(meses.mesContableDe(DateTime(2026, 9, 29, 9)), '2026-10');
    });

    test('el tramo va de una nómina a la siguiente', () {
      final meses = MesesContables.deNominas([DateTime(2026, 9, 29), DateTime(2026, 10, 30)]);
      final tramo = meses.tramoDe('2026-10');
      expect(tramo.desde, DateTime(2026, 9, 29));
      expect(tramo.hasta, DateTime(2026, 10, 30));
      expect(meses.segunNomina('2026-10'), isTrue);
    });

    test('una nómina pagada con retraso deja los días previos en el mes anterior', () {
      final meses = MesesContables.deNominas([DateTime(2026, 9, 28), DateTime(2026, 11, 2)]);
      expect(meses.inicioDe('2026-11'), DateTime(2026, 11, 2));
      expect(meses.mesContableDe(DateTime(2026, 11, 1)), '2026-10');
      expect(meses.mesContableDe(DateTime(2026, 11, 2)), '2026-11');
    });

    test('sin ninguna nómina se estima con el día 25', () {
      const meses = MesesContables({});
      expect(meses.inicioDe('2026-10'), DateTime(2026, 9, 25));
      expect(meses.segunNomina('2026-10'), isFalse);
    });

    test('un mes sin nómina se estima con el día de la más cercana', () {
      final meses = MesesContables.deNominas([DateTime(2026, 9, 29)]);
      // De noviembre no hay nómina: se usa el día 29 de la de octubre.
      expect(meses.inicioDe('2026-11'), DateTime(2026, 10, 29));
      expect(meses.segunNomina('2026-11'), isFalse);
      // Y hacia atrás igual, cuando no hay ninguna anterior de la que tirar.
      expect(meses.inicioDe('2026-08'), DateTime(2026, 7, 29));
    });

    test('la estimación recorta el día a los meses que no llegan', () {
      final meses = MesesContables.deNominas([DateTime(2027, 3, 31)]);
      // Marzo tiene 31, pero febrero solo llega al 28.
      expect(meses.inicioDe('2027-03'), DateTime(2027, 2, 28));
      expect(meses.inicioDe('2027-04'), DateTime(2027, 3, 31));
    });

    test('la estimación cruza el año sin descolocarse', () {
      final meses = MesesContables.deNominas([DateTime(2026, 12, 28)]);
      expect(meses.inicioDe('2027-01'), DateTime(2026, 12, 28));
      expect(meses.inicioDe('2027-02'), DateTime(2027, 1, 28));
      expect(meses.mesContableDe(DateTime(2026, 12, 31)), '2027-01');
    });
  });

  group('MesesContables, invariantes', () {
    /// Un año de nóminas a final de mes con dos huecos (meses que no se
    /// registraron) y una pagada con retraso, para que entren en juego tanto
    /// las nóminas reales como las estimaciones.
    final meses = MesesContables.deNominas([
      DateTime(2025, 12, 29),
      DateTime(2026, 1, 28),
      DateTime(2026, 2, 27),
      // marzo y abril sin registrar
      DateTime(2026, 5, 29), DateTime(2026, 5, 30), // los dos cobran
      DateTime(2026, 6, 26),
      DateTime(2026, 7, 4), // pagada con retraso
      DateTime(2026, 8, 28),
      // septiembre sin registrar
      DateTime(2026, 10, 30),
      DateTime(2026, 11, 27),
      DateTime(2026, 12, 29),
    ]);

    test('los meses seguidos encajan sin huecos ni solapes', () {
      var anterior = meses.tramoDe('2026-01');
      for (var m = 2; m <= 12; m++) {
        final actual = meses.tramoDe('2026-${m.toString().padLeft(2, '0')}');
        expect(actual.desde, anterior.hasta, reason: 'el mes $m no empieza donde acaba el anterior');
        expect(actual.desde.isBefore(actual.hasta), isTrue, reason: 'el mes $m está del revés');
        anterior = actual;
      }
    });

    test('cada día del año cae en el mes contable cuyo tramo lo contiene', () {
      for (var dia = DateTime(2026); dia.year == 2026; dia = dia.add(const Duration(days: 1))) {
        final tramo = meses.tramoDe(meses.mesContableDe(dia));
        expect(
          !dia.isBefore(tramo.desde) && dia.isBefore(tramo.hasta),
          isTrue,
          reason: 'el ${dia.day}/${dia.month} queda fuera de su propio tramo',
        );
      }
    });
  });
}
