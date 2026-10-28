import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_app/models/dashboard_summary.dart';

DashboardSummary resumen({double ingreso = 0, double gasto = 0, double salida = 0}) => DashboardSummary(
      mes: '2026-10',
      esMesEnCurso: true,
      gastosPorMes: [const MapEntry('2026-09', 0), MapEntry('2026-10', gasto)],
      ingresosPorMes: [const MapEntry('2026-09', 0), MapEntry('2026-10', ingreso)],
      salidasPorMes: [const MapEntry('2026-09', 0), MapEntry('2026-10', salida)],
      categoryBreakdown: const [],
      categoryComparison: const [],
      personBreakdown: const [],
      personTotalSpending: const [],
      desde: DateTime(2026, 9, 25),
      hasta: DateTime(2026, 10, 25),
      inicioSegunNomina: true,
    );

void main() {
  group('disponible', () {
    test('sin salidas es lo de siempre: ingresos menos gastos', () {
      expect(resumen(ingreso: 2000, gasto: 1200).disponible, 800);
    });

    test('lo que sale a una cuenta de fuera resta igual que el gasto', () {
      // 2000 de nómina, 1200 gastados y 100 que salieron a un ahorro que no se
      // toca: solo quedan 700 para gastar entre los dos.
      expect(resumen(ingreso: 2000, gasto: 1200, salida: 100).disponible, 700);
    });

    test('la salida no se cuela en el gasto del mes', () {
      // Es la razón de llevarla aparte: si sumara al gasto, el desglose por
      // categoría tendría 100 € que no se han consumido en nada.
      final r = resumen(ingreso: 2000, gasto: 1200, salida: 100);
      expect(r.gastoDelMes, 1200);
      expect(r.salidaDelMes, 100);
    });

    test('sacar más de lo que entra deja el disponible en negativo', () {
      expect(resumen(ingreso: 1000, gasto: 200, salida: 900).disponible, -100);
    });

    test('los totales son los del mes que se mira, el último de la serie', () {
      final r = resumen(ingreso: 2000, gasto: 1200, salida: 100);
      expect(r.ingresoDelMes, 2000);
      expect(r.gastoDelMes, 1200);
      expect(r.salidaDelMes, 100);
    });
  });
}
