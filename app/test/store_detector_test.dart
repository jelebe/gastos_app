import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_app/models/store.dart';
import 'package:gastos_app/utils/store_detector.dart';

Store tienda(String nombre) => Store(id: nombre, nombre: nombre);

const eroski = '''
EROSKI CITY
PEÑAGRANDE
-----------FACTURA SIMPLIFICADA-----------
184900012611094244
URI BROS S.L.
TELEFONO: 944441416 CIF:   B-42825323
C:8490 09-11-2026 13:28   019 01   1 4244
EUROS/TOT   ING.CLUB
GNOCHI EROSKI   1,09
TOTAL A PAGAR   13,71
www.eroski.es/comprasdetalladas
''';

/// Lo que se apunta al guardar [rawText] con la tienda [nombre].
List<LearnedFingerprint> aprende(String rawText, String nombre) =>
    [for (final h in storeFingerprints(rawText)) LearnedFingerprint(huella: h, tienda: nombre)];

void main() {
  group('storeFingerprints', () {
    test('saca el CIF aunque venga con guion', () {
      expect(storeFingerprints(eroski), contains('CIF:B42825323'));
    });

    test('saca las líneas de cabecera sin números ni las de después del primer precio', () {
      final huellas = storeFingerprints(eroski);
      expect(huellas, containsAll(['CAB:EROSKI CITY', 'CAB:URI BROS S L']));
      expect(huellas.any((h) => h.contains('GNOCHI')), isFalse);
    });
  });

  group('detectStore', () {
    test('sin nada aprendido, la reconoce por el nombre escrito en el ticket', () {
      expect(detectStore(eroski, tiendas: [tienda('Mercadona'), tienda('Eroski')]), 'Eroski');
    });

    test('entre varios nombres que encajan, el más largo', () {
      expect(detectStore(eroski, tiendas: [tienda('Eroski'), tienda('Eroski City')]), 'Eroski City');
    });

    test('un nombre corto solo cuenta en la cabecera', () {
      // "DIA" dentro de un producto no hace que el ticket sea de Dia.
      const ticket = 'SUPER PEPE\nPAN DE MOLDE DIA   1,20\nTOTAL   1,20';
      expect(detectStore(ticket, tiendas: [tienda('Dia')]), isNull);
      expect(detectStore('DIA\n$ticket', tiendas: [tienda('Dia')]), 'Dia');
    });

    test('lo aprendido manda sobre el nombre', () {
      // Lo guardaron como "Eroski Peñagrande": el CIF y la cabecera la
      // reconocen aunque el nombre no aparezca tal cual en el ticket.
      final tiendas = [tienda('Eroski'), tienda('Eroski Peñagrande')];
      expect(
        detectStore(eroski, tiendas: tiendas, aprendidas: aprende(eroski, 'Eroski Peñagrande')),
        'Eroski Peñagrande',
      );
    });

    test('una línea vista en varias tiendas no vota', () {
      const otro = 'FACTURA SIMPLIFICADA\nOTRA COSA   1,00';
      final aprendidas = [
        ...aprende('FACTURA SIMPLIFICADA', 'Lidl'),
        ...aprende('FACTURA SIMPLIFICADA', 'Mercadona'),
      ];
      expect(detectStore(otro, tiendas: [tienda('Lidl'), tienda('Mercadona')], aprendidas: aprendidas), isNull);
    });

    test('lo aprendido de una tienda que ya no está en la lista no cuenta', () {
      const ticket = 'FRUTERIA LOLA\nPLATANOS   1,20';
      expect(detectStore(ticket, tiendas: [tienda('Lidl')], aprendidas: aprende(ticket, 'Borrada')), isNull);
    });

    test('una cadena conocida se reconoce aunque no esté en la lista', () {
      expect(detectStore(eroski, tiendas: [tienda('Mercadona')]), 'Eroski');
      expect(detectStore(eroski, tiendas: []), 'Eroski');
    });

    test('si la cadena ya está en la lista, con el nombre de la lista', () {
      expect(detectStore('DIA %\nPAN   1,00', tiendas: [tienda('Día')]), 'Día');
    });

    test('una cadena conocida solo cuenta en la cabecera', () {
      // "Q.4QUESOS EROSKI" es la marca del producto, no la tienda.
      expect(detectStore('FRUTERIA LOLA\nQ.4QUESOS EROSKI   1,89', tiendas: []), isNull);
    });

    test('ignora mayúsculas y tildes al comparar con la lista', () {
      expect(
        detectStore(eroski, tiendas: [tienda('Eroski Peñagrande')], aprendidas: aprende(eroski, 'EROSKI PENAGRANDE')),
        'Eroski Peñagrande',
      );
    });
  });
}
