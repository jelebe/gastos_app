import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_app/models/category.dart';
import 'package:gastos_app/utils/product_classifier.dart';

Category _cat(String nombre, {bool peso = false, String grupo = 'Alimentación', String tipo = 'gasto'}) => Category(
      id: nombre.toLowerCase().replaceAll(' ', '-'),
      grupo: grupo,
      nombre: nombre,
      tipo: tipo,
      trackWeight: peso,
      unidadDefault: peso ? 'kg' : 'unidad',
    );

LearnedLine _aprendida(String texto, Category categoria, {bool alPeso = false}) =>
    LearnedLine(clave: lineKey(texto), alPeso: alPeso, decision: categoria.id);

LearnedLine _noProducto(String texto) =>
    LearnedLine(clave: lineKey(texto), alPeso: false, decision: LearnedLine.noProducto);

void main() {
  // Una muestra de las categorías reales del hogar, con las parejas que solo
  // se distinguen por ir al peso o por una palabra.
  final queso = _cat('Queso', peso: true);
  final quesoCuna = _cat('Queso cuña');
  final quesoRallado = _cat('Queso rallado');
  final quesoBurgos = _cat('Queso de burgos');
  final pollo = _cat('Pollo', peso: true);
  final polloBandeja = _cat('Pollo bandeja');
  final pechugaPollo = _cat('Pechuga Pollo corte', peso: true);
  final pavo = _cat('Pavo', peso: true);
  final pechugaPavo = _cat('Pechuga Pavo corte', peso: true);
  final judias = _cat('Judías verdes', peso: true);
  final judiasTarro = _cat('Judías verdes tarro');
  final tomateFrito = _cat('Tomate frito');
  final tomates = _cat('Tomates', peso: true);
  final palomitas = _cat('Palomitas (snack)');
  final papelHigienico = _cat('Papel higiénico', grupo: 'Limpieza');
  final nomina = _cat('Nómina', grupo: 'Ingresos', tipo: 'ingreso');
  final categorias = [
    queso, quesoCuna, quesoRallado, quesoBurgos, pollo, polloBandeja, pechugaPollo, pavo, pechugaPavo,
    judias, judiasTarro, tomateFrito, tomates, palomitas, papelHigienico, nomina,
  ];

  ProductClassifier clasificador([List<LearnedLine> aprendidas = const []]) =>
      ProductClassifier(categorias: categorias, aprendidas: aprendidas);

  group('lineKey', () {
    test('quita acentos, signos y números sueltos', () {
      expect(lineKey('JUDÍAS VERDES ALIPENDE 360G'), 'JUDIAS VERDES ALIPENDE G');
      expect(lineKey('P.HIGIENICO LANTA 6U 4C PER'), 'P HIGIENICO LANTA U C PER');
      expect(lineKey('MASA PIZZA ALIPENDE 260G   C   2,266'), 'MASA PIZZA ALIPENDE G C');
    });

    test('corrige ceros y unos leídos en lugar de letras', () {
      expect(lineKey('HUEVOS SUELTAS GALLINER0 AL C'), lineKey('HUEVOS SUELTAS GALLINERO AL C'));
      expect(lineKey('YOGUR LIQUIDO ALIPENDE 1K F'), lineKey('YOGUR LIQUIDO ALIPENDE IK F'));
    });
  });

  group('lo ya aprendido', () {
    test('la misma línea sale como aprendida, sin revisar', () {
      final g = clasificador([_aprendida('QUESO SEMICURAD0 CUNA ALIPE', quesoCuna)])
          .classify('QUESO SEMICURADO CUNA ALIPE', alPeso: false)!;

      expect(g.categoria, quesoCuna);
      expect(g.certeza, Certeza.aprendida);
    });

    test('reconoce la misma línea con letras mal leídas', () {
      final c = clasificador([
        _aprendida('QUESO MOZZARELLA RALLADO', quesoRallado),
        _aprendida('TOMATE TRITURAD0 ALIPENDE 4', tomateFrito),
      ]);

      expect(c.classify('OUESO MOZZAPELLA RALLADO AL', alPeso: false)!.categoria, quesoRallado);
      expect(c.classify('TOMATE TRIIURADO ALIPENDE 4', alPeso: false)!.categoria, tomateFrito);
    });

    test('la misma línea al peso y por unidad se aprende por separado', () {
      final c = clasificador([
        _aprendida('QUESO SEMICURADO', queso, alPeso: true),
        _aprendida('QUESO SEMICURADO', quesoCuna),
      ]);

      expect(c.classify('QUESO SEMICURADO', alPeso: true)!.categoria, queso);
      expect(c.classify('QUESO SEMICURADO', alPeso: false)!.categoria, quesoCuna);
    });

    test('no confunde pollo con pavo aunque el resto del texto sea igual', () {
      final g = clasificador([_aprendida('PECHUGA PAVO ASADA   FR', pechugaPavo, alPeso: true)])
          .classify('PECHUGA POLLO ASADA   FR', alPeso: true)!;

      expect(g.categoria, pechugaPollo);
    });

    test('ignora lo aprendido para categorías que ya no existen', () {
      final borrada = LearnedLine(clave: lineKey('PAN BURGUER BRIOCHE'), alPeso: false, decision: 'alimentacion-pan');

      expect(clasificador([borrada]).classify('PAN BURGUER BRIOCHE', alPeso: false), isNull);
    });
  });

  group('por el nombre de la categoría', () {
    test('al peso o por unidad decide entre categorías parecidas', () {
      final c = clasificador();

      expect(c.classify('QUESO SEMICURADO', alPeso: true)!.categoria, queso);
      expect(c.classify('QUESO SEMICURADO CUNA 250G', alPeso: false)!.categoria, quesoCuna);
      expect(c.classify('JUDIAS VERDES ALIPENDE 360G', alPeso: false)!.categoria, judiasTarro);
      expect(c.classify('JUDIAS VERDES', alPeso: true)!.categoria, judias);
      expect(c.classify('POLLO ENTERO BANDEJA', alPeso: false)!.categoria, polloBandeja);
      expect(c.classify('POLLO ENTERO', alPeso: true)!.categoria, pollo);
    });

    test('prefiere la categoría con más palabras en común', () {
      expect(clasificador().classify('PECHUGA POLLO ASADA FR', alPeso: true)!.categoria, pechugaPollo);
    });

    test('tolera abreviaturas y palabras partidas por el escáner', () {
      final c = clasificador();

      expect(c.classify('P.HIGIENICO LANTA 6U', alPeso: false)!.categoria, papelHigienico);
      expect(c.classify('PALOMI TAS S/GLUTEN RISI 90G', alPeso: false)!.categoria, palomitas);
    });

    test('lo que sale por nombre siempre va marcado para revisar', () {
      expect(clasificador().classify('QUESO RALLADO', alPeso: false)!.certeza, Certeza.probable);
    });

    test('nunca propone categorías de ingresos', () {
      expect(clasificador().classify('NOMINA', alPeso: false), isNull);
    });

    test('si no se parece a nada, no propone nada', () {
      expect(clasificador().classify('DIADEMA CUMPLEANOS', alPeso: false), isNull);
      expect(clasificador().classify('1234 5,00', alPeso: false), isNull);
    });
  });

  group('lo que no es producto', () {
    test('quita una línea igual a otra que ya se quitó', () {
      final g = clasificador([_noProducto('AHORRAMAS SIN TICKET')]).classify('Ahorramas sin ticket', alPeso: false)!;

      expect(g.noProducto, isTrue);
      expect(g.categoria, isNull);
    });

    test('quita también la misma línea con alguna letra mal leída, pero no productos parecidos', () {
      final c = clasificador([
        _noProducto('AHORRAMAS SIN TICKET'),
        _noProducto('TOTAL COMPRA TARJETA'),
        _aprendida('QUESO RALLADO', quesoRallado),
        _aprendida('TOMATE TRITURADO ALIPENDE', tomateFrito),
        _aprendida('POLLO ENTERO BANDEJA', polloBandeja),
      ]);

      expect(c.classify('TOTAL COMPRA TARJFTA', alPeso: false)!.noProducto, isTrue);
      expect(c.classify('AHORRAMAS SIN TIQKET', alPeso: false)!.noProducto, isTrue);
      expect(c.classify('TARTA DE QUESO', alPeso: false)?.noProducto ?? false, isFalse);
      expect(c.classify('TOMATE TRITURADO ALIPENDE', alPeso: false)!.categoria, tomateFrito);
    });
  });
}
