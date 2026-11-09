import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_app/utils/formato.dart';

void main() {
  group('numeroEs', () {
    test('coma decimal', () {
      expect(numeroEs(12.4), '12,40');
      expect(numeroEs(0.05), '0,05');
    });

    test('punto de miles a partir de cuatro cifras', () {
      expect(numeroEs(999.99), '999,99');
      expect(numeroEs(1977.02), '1.977,02');
      expect(numeroEs(12345.6), '12.345,60');
      expect(numeroEs(1234567.89), '1.234.567,89');
    });

    test('negativos', () {
      expect(numeroEs(-1977.02), '-1.977,02');
      expect(numeroEs(-0.5), '-0,50');
    });

    test('un negativo que redondea a cero no sale con signo', () {
      // "-0,00" no es nada que nadie quiera leer.
      expect(numeroEs(-0.001), '0,00');
      expect(numeroEs(-0.0), '0,00');
    });

    test('sin decimales', () {
      expect(numeroEs(1977.6, decimales: 0), '1.978');
      expect(numeroEs(0.4, decimales: 0), '0');
    });
  });

  group('euros', () {
    test('lleva el símbolo detrás, separado', () {
      expect(euros(1977.02), '1.977,02 €');
      expect(euros(0), '0,00 €');
    });

    test('con signo, solo los positivos llevan el más', () {
      expect(euros(120.5, conSigno: true), '+120,50 €');
      expect(euros(-120.5, conSigno: true), '-120,50 €');
      expect(euros(0, conSigno: true), '0,00 €');
    });

    test('sin pedir signo, los positivos van limpios', () {
      expect(euros(120.5), '120,50 €');
    });
  });

  group('pesoLegible', () {
    test('en gramos por debajo del kilo, sin decimales', () {
      expect(pesoLegible(850), '850 g');
      expect(pesoLegible(999.4), '999 g');
    });

    test('en kilos a partir del kilo', () {
      expect(pesoLegible(1000), '1,00 kg');
      expect(pesoLegible(1200), '1,20 kg');
      expect(pesoLegible(12500), '12,50 kg');
    });
  });
}
