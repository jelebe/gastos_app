import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_app/models/store.dart';

Store tienda(String nombre, {String? grupo}) => Store(id: nombre, nombre: nombre, grupo: grupo);

void main() {
  group('Store.fromFirestore', () {
    test('un grupo vacío o en blanco es no tener grupo', () {
      expect(Store.fromFirestore('1', {'nombre': 'Lidl', 'grupo': ''}).grupo, isNull);
      expect(Store.fromFirestore('1', {'nombre': 'Lidl', 'grupo': '   '}).grupo, isNull);
      expect(Store.fromFirestore('1', {'nombre': 'Lidl'}).grupo, isNull);
    });

    test('sin grupo se enseña bajo la etiqueta de cajón', () {
      expect(Store.fromFirestore('1', {'nombre': 'Lidl'}).grupoVisible, sinGrupo);
      expect(tienda('Lidl', grupo: 'Supermercados').grupoVisible, 'Supermercados');
    });
  });

  group('agrupaTiendas', () {
    test('agrupa y ordena los grupos alfabéticamente', () {
      final grupos = agrupaTiendas([
        tienda('Mercadona', grupo: 'Supermercados'),
        tienda('Bar Paco', grupo: 'Bares'),
        tienda('Lidl', grupo: 'Supermercados'),
      ]);
      expect(grupos.map((g) => g.key), ['Bares', 'Supermercados']);
      expect(grupos.last.value.map((t) => t.nombre), ['Lidl', 'Mercadona']);
    });

    test('las tiendas van por orden alfabético dentro de su grupo', () {
      final grupos = agrupaTiendas([
        tienda('mercadona', grupo: 'Supermercados'),
        tienda('Ahorramás', grupo: 'Supermercados'),
        tienda('Lidl', grupo: 'Supermercados'),
      ]);
      expect(grupos.single.value.map((t) => t.nombre), ['Ahorramás', 'Lidl', 'mercadona']);
    });

    test('las que no tienen grupo van al final, no en su letra', () {
      // Es el cajón de lo que falta por colocar: alfabéticamente "Sin grupo"
      // caería entre medias y parecería un grupo más.
      final grupos = agrupaTiendas([
        tienda('Suelta'),
        tienda('Bar Paco', grupo: 'Bares'),
        tienda('Iberdrola', grupo: 'Zuministros'),
      ]);
      expect(grupos.map((g) => g.key), ['Bares', 'Zuministros', sinGrupo]);
    });

    test('sin tiendas no hay grupos', () {
      expect(agrupaTiendas([]), isEmpty);
    });
  });
}
