import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_app/models/product_summary.dart';

ProductPurchase compra(
  String mes,
  int dia,
  double precio, {
  double? pesoGramos,
  double? precioPorKilo,
  String? comercio,
  bool compartido = true,
}) {
  final partes = mes.split('-');
  return (
    precio: precio,
    pesoGramos: pesoGramos,
    precioPorKilo: precioPorKilo,
    fecha: DateTime(int.parse(partes[0]), int.parse(partes[1]), dia),
    comercio: comercio,
    pagadoPor: 'Cano',
    compartido: compartido,
    mesContable: mes,
  );
}

ProductSummary resumen(List<ProductPurchase> compras, {List<String>? meses}) => resumenDeProducto(
      producto: 'Tomates',
      grupo: 'Alimentación',
      meses: meses ?? const ['2026-09', '2026-10'],
      compras: compras,
    );

void main() {
  group('resumenDeProducto', () {
    test('sin compras, todo a cero y sin precios que contar', () {
      final ficha = resumen([]);
      expect(ficha.total, 0);
      expect(ficha.compras, 0);
      expect(ficha.tienePrecioPorKilo, isFalse);
      expect(ficha.masBarato, isNull);
      expect(ficha.porMes.map((e) => e.value), everyElement(0));
    });

    test('suma el total y cuenta las compras', () {
      final ficha = resumen([compra('2026-10', 4, 2.15), compra('2026-10', 12, 1.80)]);
      expect(ficha.total, closeTo(3.95, 0.001));
      expect(ficha.compras, 2);
    });

    test('reparte por mes y deja a cero los meses sin compras', () {
      final ficha = resumen(
        [compra('2026-10', 4, 2.15)],
        meses: const ['2026-08', '2026-09', '2026-10'],
      );
      expect(ficha.porMes.map((e) => e.key), ['2026-08', '2026-09', '2026-10']);
      expect(ficha.porMes.map((e) => e.value), [0, 0, 2.15]);
      expect(ficha.totalDelMes, 2.15);
    });

    test('la lista del mes solo trae las compras del mes que se mira', () {
      // Lo que motivó separarla: al abrir la ficha desde octubre salían
      // también las compras de septiembre.
      final ficha = resumen([compra('2026-09', 10, 1.00), compra('2026-10', 4, 2.15), compra('2026-10', 12, 1.80)]);
      expect(ficha.lineasDelMes.map((l) => l.precio), [1.80, 2.15]);
      expect(ficha.lineas, hasLength(3));
    });

    test('una compra fuera de la ventana suma al total pero no a ningún mes', () {
      // Puede pasar con un ticket de fecha rara: mejor que salga en el total
      // y en la lista que no salga en ninguna parte.
      final ficha = resumen([compra('2026-01', 9, 5.00)]);
      expect(ficha.total, 5.00);
      expect(ficha.porMes.map((e) => e.value), everyElement(0));
    });

    test('el precio medio por kilo va ponderado por peso, no promediando precios', () {
      // 2 kg a 1 €/kg y 0,5 kg a 3 €/kg: la media real es 1,40 €/kg, no 2.
      final ficha = resumen([
        compra('2026-10', 4, 2.00, pesoGramos: 2000, precioPorKilo: 1.00),
        compra('2026-10', 8, 1.50, pesoGramos: 500, precioPorKilo: 3.00),
      ]);
      expect(ficha.pesoTotalGramos, 2500);
      expect(ficha.precioMedioPorKilo, closeTo(1.40, 0.001));
    });

    test('lo vendido por unidad no entra en el precio por kilo', () {
      final ficha = resumen([
        compra('2026-10', 4, 2.00, pesoGramos: 1000, precioPorKilo: 2.00),
        compra('2026-10', 8, 9.99), // sin peso: una unidad
      ]);
      expect(ficha.total, closeTo(11.99, 0.001));
      expect(ficha.pesoTotalGramos, 1000);
      expect(ficha.precioMedioPorKilo, closeTo(2.00, 0.001));
    });

    test('sin nada al peso no hay precio por kilo', () {
      final ficha = resumen([compra('2026-10', 4, 1.20)]);
      expect(ficha.pesoTotalGramos, isNull);
      expect(ficha.precioMedioPorKilo, isNull);
      expect(ficha.tienePrecioPorKilo, isFalse);
    });

    test('encuentra la compra más barata por kilo, con dónde y cuándo', () {
      final ficha = resumen([
        compra('2026-10', 4, 2.40, pesoGramos: 1000, precioPorKilo: 2.40, comercio: 'Mercadona'),
        compra('2026-10', 9, 1.29, pesoGramos: 1000, precioPorKilo: 1.29, comercio: 'Lidl'),
        compra('2026-10', 14, 1.90, pesoGramos: 1000, precioPorKilo: 1.90, comercio: 'Carrefour'),
      ]);
      expect(ficha.masBarato?.precioPorKilo, closeTo(1.29, 0.001));
      expect(ficha.masBarato?.comercio, 'Lidl');
      expect(ficha.masBarato?.fecha, DateTime(2026, 10, 9));
    });

    test('si la línea no traía precio por kilo, se saca del precio y el peso', () {
      // Las líneas viejas pueden no tenerlo guardado.
      final ficha = resumen([compra('2026-10', 4, 3.00, pesoGramos: 1500)]);
      expect(ficha.masBarato?.precioPorKilo, closeTo(2.00, 0.001));
      expect(ficha.precioMedioPorKilo, closeTo(2.00, 0.001));
    });

    test('las compras salen de la más reciente a la más antigua', () {
      final ficha = resumen([
        compra('2026-10', 4, 1.00),
        compra('2026-10', 20, 1.00),
        compra('2026-09', 30, 1.00),
      ]);
      expect(ficha.lineas.map((l) => l.fecha.day), [20, 4, 30]);
    });

    test('un peso a cero no cuenta como venta al peso', () {
      final ficha = resumen([compra('2026-10', 4, 1.20, pesoGramos: 0)]);
      expect(ficha.pesoTotalGramos, isNull);
      expect(ficha.masBarato, isNull);
    });
  });

  group('resumenDeProducto, precios por tienda', () {
    test('cada tienda con su media ponderada, de la más barata a la más cara', () {
      final ficha = resumen([
        // Mercadona: 1 kg a 2 € y 1 kg a 3 € → 2,50 €/kg
        compra('2026-10', 4, 2.00, pesoGramos: 1000, comercio: 'Mercadona'),
        compra('2026-10', 8, 3.00, pesoGramos: 1000, comercio: 'Mercadona'),
        compra('2026-10', 9, 1.29, pesoGramos: 1000, comercio: 'Lidl'),
      ]);
      expect(ficha.porComercio.map((p) => p.comercio), ['Lidl', 'Mercadona']);
      expect(ficha.porComercio.first.precioPorKilo, closeTo(1.29, 0.001));
      expect(ficha.porComercio.last.precioPorKilo, closeTo(2.50, 0.001));
      expect(ficha.porComercio.last.compras, 2);
      expect(ficha.sePuedeCompararTiendas, isTrue);
    });

    test('con una sola tienda no hay nada que comparar ni ahorro que calcular', () {
      final ficha = resumen([compra('2026-10', 4, 2.00, pesoGramos: 1000, comercio: 'Lidl')]);
      expect(ficha.sePuedeCompararTiendas, isFalse);
      expect(ficha.ahorroPosible, isNull);
    });

    test('el ahorro es lo mismo comprado siempre en la más barata', () {
      final ficha = resumen([
        compra('2026-10', 4, 4.00, pesoGramos: 1000, comercio: 'Mercadona'), // 4 €/kg
        compra('2026-10', 9, 2.00, pesoGramos: 1000, comercio: 'Lidl'), // 2 €/kg
      ]);
      // 2 kg a 2 €/kg serían 4 €; se gastaron 6 € → 2 € de más.
      expect(ficha.ahorroPosible, closeTo(2.00, 0.001));
    });

    test('lo comprado sin tienda apuntada no entra en la comparativa', () {
      final ficha = resumen([
        compra('2026-10', 4, 2.00, pesoGramos: 1000, comercio: 'Lidl'),
        compra('2026-10', 8, 9.00, pesoGramos: 1000),
      ]);
      expect(ficha.porComercio, hasLength(1));
      // Pero sí en el total y en la media global, que no son de tiendas.
      expect(ficha.total, closeTo(11.00, 0.001));
    });

    test('lo vendido por unidad no entra: sin gramos no hay precio por kilo', () {
      final ficha = resumen([
        compra('2026-10', 4, 2.00, pesoGramos: 1000, comercio: 'Lidl'),
        compra('2026-10', 8, 3.00, comercio: 'Mercadona'),
      ]);
      expect(ficha.porComercio.map((p) => p.comercio), ['Lidl']);
      expect(ficha.sePuedeCompararTiendas, isFalse);
    });
  });
}
