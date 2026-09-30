import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_app/models/basket_inflation.dart';

ProductPricePoint punto(String producto, String mes, {required double gastado, required double gramos}) =>
    (producto: producto, mes: mes, gastado: gastado, gramos: gramos);

const antes = ['2026-05', '2026-06', '2026-07'];
const ahora = ['2026-08', '2026-09', '2026-10'];

BasketInflation calcula(List<ProductPricePoint> puntos) =>
    inflacionDeCesta(puntos: puntos, mesesAntes: antes, mesesAhora: ahora);

void main() {
  group('inflacionDeCesta', () {
    test('sin datos no dice cero, dice que no se sabe', () {
      final r = calcula([]);
      expect(r.hayDatos, isFalse);
      expect(r.variacion, isNull);
    });

    test('un producto solo en un tramo no se puede comparar', () {
      final r = calcula([punto('Tomates', '2026-10', gastado: 2, gramos: 1000)]);
      expect(r.hayDatos, isFalse);
      expect(r.productosDescartados, 1);
    });

    test('una subida limpia del 50 %', () {
      final r = calcula([
        punto('Tomates', '2026-06', gastado: 2.00, gramos: 1000), // 2,00 €/kg
        punto('Tomates', '2026-09', gastado: 3.00, gramos: 1000), // 3,00 €/kg
      ]);
      expect(r.variacion, closeTo(0.5, 0.0001));
      expect(r.cambios.single.precioAntes, closeTo(2.0, 0.0001));
      expect(r.cambios.single.precioAhora, closeTo(3.0, 0.0001));
    });

    test('una bajada sale en negativo', () {
      final r = calcula([
        punto('Tomates', '2026-06', gastado: 4.00, gramos: 1000),
        punto('Tomates', '2026-09', gastado: 3.00, gramos: 1000),
      ]);
      expect(r.variacion, closeTo(-0.25, 0.0001));
      expect(r.bajadas, hasLength(1));
      expect(r.subidas, isEmpty);
    });

    test('pesa por lo que se gasta ahora, no por producto', () {
      // El aceite dobla de precio y se lleva 30 € al mes; el perejil dobla
      // también pero son 30 céntimos. Una media simple daría +100 % en los dos
      // casos; ponderada, manda el aceite, pero el perejil casi no mueve nada.
      final r = calcula([
        punto('Aceite', '2026-06', gastado: 15, gramos: 3000), // 5 €/kg
        punto('Aceite', '2026-09', gastado: 30, gramos: 3000), // 10 €/kg → x2
        punto('Perejil', '2026-06', gastado: 0.30, gramos: 100), // 3 €/kg
        punto('Perejil', '2026-09', gastado: 0.33, gramos: 100), // 3,3 €/kg → +10 %
      ]);
      // (30 × 2 + 0,33 × 1,1) / 30,33 - 1 ≈ 0,99
      expect(r.variacion, closeTo(0.99, 0.01));
    });

    test('varios meses del mismo tramo se promedian ponderados por cantidad', () {
      final r = calcula([
        // Antes: 1 kg a 2 € y 3 kg a 4 € → 14 € / 4 kg = 3,50 €/kg
        punto('Tomates', '2026-05', gastado: 2, gramos: 1000),
        punto('Tomates', '2026-07', gastado: 12, gramos: 3000),
        // Ahora: 2 kg a 7 € → 3,50 €/kg, o sea igual
        punto('Tomates', '2026-09', gastado: 7, gramos: 2000),
      ]);
      expect(r.variacion, closeTo(0, 0.0001));
    });

    test('los cambios salen de la mayor subida a la mayor bajada', () {
      final r = calcula([
        punto('Sube', '2026-06', gastado: 1, gramos: 1000),
        punto('Sube', '2026-09', gastado: 2, gramos: 1000), // +100 %
        punto('Igual', '2026-06', gastado: 1, gramos: 1000),
        punto('Igual', '2026-09', gastado: 1, gramos: 1000), // 0 %
        punto('Baja', '2026-06', gastado: 2, gramos: 1000),
        punto('Baja', '2026-09', gastado: 1, gramos: 1000), // -50 %
      ]);
      expect(r.cambios.map((c) => c.producto), ['Sube', 'Igual', 'Baja']);
      expect(r.subidas.map((c) => c.producto), ['Sube']);
      expect(r.bajadas.map((c) => c.producto), ['Baja']);
    });

    test('lo que no va al peso no entra', () {
      final r = calcula([
        punto('Tomates', '2026-06', gastado: 2, gramos: 0),
        punto('Tomates', '2026-09', gastado: 3, gramos: 0),
      ]);
      expect(r.hayDatos, isFalse);
      expect(r.cambios, isEmpty);
    });

    test('los meses fuera de la ventana se ignoran', () {
      final r = calcula([
        punto('Tomates', '2026-01', gastado: 1, gramos: 1000),
        punto('Tomates', '2026-09', gastado: 3, gramos: 1000),
      ]);
      expect(r.hayDatos, isFalse);
    });
  });
}
