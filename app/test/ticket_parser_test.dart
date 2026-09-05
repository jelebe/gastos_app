import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_app/utils/ticket_parser.dart';

void main() {
  group('isNoiseLine', () {
    test('descarta direcciones', () {
      expect(isNoiseLine('C/ MAYOR 15, LOCAL 2'), isTrue);
      expect(isNoiseLine('AVDA DE LA CONSTITUCION 4'), isTrue);
      expect(isNoiseLine('28001 MADRID'), isTrue);
    });

    test('descarta identificacion fiscal y contacto', () {
      expect(isNoiseLine('CIF: A12345678'), isTrue);
      expect(isNoiseLine('TEL: 912345678'), isTrue);
      expect(isNoiseLine('912345678'), isTrue);
      expect(isNoiseLine('WWW.SUPERMERCADO.ES'), isTrue);
    });

    test('descarta cabecera, pie y totales del ticket', () {
      expect(isNoiseLine('FACTURA SIMPLIFICADA'), isTrue);
      expect(isNoiseLine('OPERADOR: 042'), isTrue);
      expect(isNoiseLine('GRACIAS POR SU VISITA'), isTrue);
      expect(isNoiseLine('IVA 21%'), isTrue);
      expect(isNoiseLine('TARJETA BANCARIA'), isTrue);
      expect(isNoiseLine('05/09/2026 14:32'), isTrue);
    });

    test('descarta separadores sin letras', () {
      expect(isNoiseLine('------------------'), isTrue);
      expect(isNoiseLine('8412345678901'), isTrue);
    });

    test('no descarta productos normales', () {
      expect(isNoiseLine('LECHE ENTERA 1L'), isFalse);
      expect(isNoiseLine('TOMATE RAMA'), isFalse);
      expect(isNoiseLine('CERVEZA LATA 33CL'), isFalse);
    });

    test('no descarta productos con un porcentaje real en el nombre', () {
      // "0%" aquí es parte del nombre del producto (queso sin grasa), no una
      // fila de desglose de IVA: no debe confundirse con "B  21,00%  ...".
      expect(isNoiseLine('QUESO BLANCO 0% M. GRASA ALI'), isFalse);
    });

    test('descarta las lineas reales de cabecera de un ticket de Ahorramas', () {
      expect(isNoiseLine('AHORRaMaS'), isTrue); // logo estilizado, mayus/minus erraticas
      expect(isNoiseLine('02-09-2026 20:14:40 Caja: 8 Tique: 100'), isTrue);
      expect(isNoiseLine('28029 - MADRID (MADRID)'), isTrue);
      expect(isNoiseLine('AHORRAMAS,S.A. A28600278'), isTrue); // CIF suelto sin etiqueta "CIF:"
    });
  });

  group('parseReceiptLines', () {
    test('ignora ruido y detecta precio simple al final', () {
      final result = parseReceiptLines('''
SUPERMERCADO EJEMPLO S.L.
C/ MAYOR 15
28001 MADRID
CIF: A12345678
LECHE ENTERA 1L         0,89
TOTAL                   0,89
''');
      expect(result, hasLength(1));
      expect(result.first.descripcion, 'LECHE ENTERA 1L');
      expect(result.first.precioTotal, 0.89);
    });

    test('detecta precio por kilo en una sola linea', () {
      final result = parseReceiptLines('TOMATE RAMA 0,608 kg 1,49 €/kg 0,91');
      expect(result, hasLength(1));
      expect(result.first.descripcion, 'TOMATE RAMA');
      expect(result.first.precioTotal, 0.91);
      expect(result.first.pesoGramos, closeTo(608, 0.01));
    });

    test('detecta precio por kilo cuando el peso viene en la linea siguiente', () {
      final result = parseReceiptLines('''
PLATANO
0,352 kg x 1,09 €/kg                        0,38
''');
      expect(result, hasLength(1));
      expect(result.first.descripcion, 'PLATANO');
      expect(result.first.precioTotal, 0.38);
      expect(result.first.pesoGramos, closeTo(352, 0.01));
    });

    test('calcula el total por peso si el ticket no lo repite', () {
      final result = parseReceiptLines('QUESO LONCHAS 0,150 kg x 9,95 €/kg');
      expect(result.first.precioTotal, 1.49); // 0.150 * 9.95 = 1.4925 -> 1.49
      expect(result.first.pesoGramos, closeTo(150, 0.01));
    });

    test('explota "cantidad x precio" en lineas individuales (2 cervezas)', () {
      final result = parseReceiptLines('CERVEZA LATA 33CL 2 x 0,90 1,80');
      expect(result, hasLength(2));
      expect(result[0].descripcion, 'CERVEZA LATA 33CL');
      expect(result[0].precioTotal, 0.90);
      expect(result[1].descripcion, 'CERVEZA LATA 33CL');
      expect(result[1].precioTotal, 0.90);
    });

    test('explota formato Mercadona "cantidad al principio"', () {
      final result = parseReceiptLines('2 CERVEZA TERCIO 0,45 0,90');
      expect(result, hasLength(2));
      for (final item in result) {
        expect(item.descripcion, 'CERVEZA TERCIO');
        expect(item.precioTotal, 0.45);
      }
    });

    test('reparte sin descuadre cuando el total no es multiplo exacto', () {
      final result = parseReceiptLines('YOGUR PACK 3 x 0,33 1,00');
      expect(result, hasLength(3));
      final total = result.fold<double>(0, (sum, i) => sum + (i.precioTotal ?? 0));
      expect(total, closeTo(1.00, 0.001));
    });

    test('no confunde "1,5L" de un pack con un precio unitario de 2 decimales', () {
      final result = parseReceiptLines('AGUA MINERAL PACK 6X1,5L 3,50');
      expect(result, hasLength(1));
      expect(result.first.precioTotal, 3.50);
    });

    test('fusiona la continuacion aunque el OCR le pegue ruido detras del precio', () {
      // Caso real: el OCR coló texto suelto (probablemente de la marca de
      // agua de seguridad del papel) pegado justo después del precio.
      final result = parseReceiptLines('''
CERVEZA RUBIA ESTRELLA GALI
2 Un x 0,90€/UnOUDETTO Bae 1,80€
''');
      expect(result, hasLength(2));
      for (final item in result) {
        expect(item.descripcion, 'CERVEZA RUBIA ESTRELLA GALI');
        expect(item.precioTotal, 0.90);
      }
    });

    test('NO fusiona si el patron de cantidad va detras de un nombre real (tamano de pack)', () {
      final result = parseReceiptLines('''
YOGUR SIN PRECIO PROPIO
COCA COLA PACK 2X1,5L 1,50
''');
      // La primera linea se queda sin precio: la segunda es un producto
      // nuevo (el "2X1,5L" es el tamaño del pack, no una cantidad suelta),
      // no la continuación de "YOGUR SIN PRECIO PROPIO".
      expect(result, hasLength(2));
      expect(result[0].descripcion, 'YOGUR SIN PRECIO PROPIO');
      expect(result[0].precioTotal, isNull);
      expect(result[1].descripcion, 'COCA COLA PACK 2X1,5L');
      expect(result[1].precioTotal, 1.50);
    });

    test('fusiona "N UN x precio" (con la palabra unidad) en la linea siguiente', () {
      final result = parseReceiptLines('''
CERVEZA LATA 33CL
2 UN X 0,90                                    1,80
''');
      expect(result, hasLength(2));
      for (final item in result) {
        expect(item.descripcion, 'CERVEZA LATA 33CL');
        expect(item.precioTotal, 0.90);
      }
    });

    test('fusiona "N UD x precio" en la linea siguiente', () {
      final result = parseReceiptLines('''
YOGUR NATURAL PACK 4
3 UD x 0,50                                    1,50
''');
      expect(result, hasLength(3));
      for (final item in result) {
        expect(item.descripcion, 'YOGUR NATURAL PACK 4');
        expect(item.precioTotal, 0.50);
      }
    });

    test('detecta "N UN x precio" cuando esta en la misma linea que la descripcion', () {
      final result = parseReceiptLines('CERVEZA LATA 33CL 2 UN X 0,90 1,80');
      expect(result, hasLength(2));
      for (final item in result) {
        expect(item.descripcion, 'CERVEZA LATA 33CL');
        expect(item.precioTotal, 0.90);
      }
    });

    test('no desplaza el precio de la siguiente linea real tras una linea "N UN x precio"', () {
      final result = parseReceiptLines('''
CERVEZA LATA 33CL
2 UN X 0,90                                    1,80
PAN DE MOLDE                                   1,25
''');
      expect(result, hasLength(3));
      expect(result[0].descripcion, 'CERVEZA LATA 33CL');
      expect(result[0].precioTotal, 0.90);
      expect(result[1].descripcion, 'CERVEZA LATA 33CL');
      expect(result[1].precioTotal, 0.90);
      expect(result[2].descripcion, 'PAN DE MOLDE');
      expect(result[2].precioTotal, 1.25);
    });

    test('ticket real de Ahorramas: descarta cabecera/pie y calcula bien los 6 articulos', () {
      // Texto reconstruido tal y como lo produce _reconstructReadingOrder:
      // cada fila real del ticket ya con sus columnas unidas (nombre, letra
      // de tipo de IVA, precio), en vez de todos los nombres seguidos y
      // luego todos los precios como agrupaba ML Kit por bloques.
      final result = parseReceiptLines('''
AHORRaMaS
AVDA. BETANZOS, 37
28029 - MADRID (MADRID)
AHORRAMAS,S.A. A28600278
02-09-2026 20:14:40 Caja: 8 Tique: 100
COLINES INTEGRALES ALIPENDE   C   0,70€
LIMA BANDEJA   C   2,44€
AGUACATE BANDEJA   C   3,35€
CERVEZA RUBIA ESTRELLA GALI
2 Un x 0,90€/Un   B   1,80€
MANGO
0,530 Kg x 3,59€/Kg   C   1,90€
TOTAL   5 TR   10,19€
Tarjeta..........   10,19€
TOTAL ENTREGADO EUR.   10,19€
CAMBIO EUR.........   00,00€
GRACIAS POR SU CONFIANZA
TELEFONO ATENCION AL CLIENTE: 900 113 213
VISITE NUESTRA WEB: WWW.AHORRAMAS.COM
Numero de articulos: 6
Nº Factura Simplificada: S103108/0045209
S103108/0045209
Tipo   Base   Iva   Total
B   21,00%   1,49   0,31   1,80
C   04,00%   8,07   0,32   8,39
''');
      expect(result, hasLength(6));
      expect(result[0].descripcion, 'COLINES INTEGRALES ALIPENDE');
      expect(result[0].precioTotal, 0.70);
      expect(result[1].descripcion, 'LIMA BANDEJA');
      expect(result[1].precioTotal, 2.44);
      expect(result[2].descripcion, 'AGUACATE BANDEJA');
      expect(result[2].precioTotal, 3.35);
      expect(result[3].descripcion, 'CERVEZA RUBIA ESTRELLA GALI');
      expect(result[3].precioTotal, 0.90);
      expect(result[4].descripcion, 'CERVEZA RUBIA ESTRELLA GALI');
      expect(result[4].precioTotal, 0.90);
      expect(result[5].descripcion, 'MANGO');
      expect(result[5].precioTotal, 1.90);
      expect(result[5].pesoGramos, closeTo(530, 0.01));
      final total = result.fold<double>(0, (sum, i) => sum + (i.precioTotal ?? 0));
      expect(total, closeTo(10.19, 0.001));
    });

    test('ticket real de Flying Tiger: formato tabular cantidad+codigo+descripcion+total', () {
      // Nota: la primera línea del ticket real es el logo "flying tiger
      // copenhagen" en minúsculas sin sufijo legal (S.L., S.A...), que no
      // hay forma genérica de distinguir de un nombre de producto real; se
      // omite aquí porque no es lo que este test quiere comprobar (ver el
      // test de isNoiseLine para la limitación conocida de nombres de tienda).
      final result = parseReceiptLines('''
TIGER STORES SPAIN, S.L.U.
C/ ORENSE, 34, 10, 28020, MADRID
C. Goya 20 28001 Madrid
Fecha: 02/09/2026 17:54:52
Factura simplificada: A/639827
Le atendio: 53092 SHARON ANGIE
UNID CODIGO DESCRIPCION TOTAL
1 3073611 CALABAZA LUMINOSA G 8,00
1 3056752 BOLSA DE PAPEL. PEQ 0,50
1 3055619 SELLOS. 9 UDS 3,50
1 3032684 DIADEMA CUMPLEAÑOS 2,00
1 3074143 PLANIFICADOR DE EST 7,00
Formas de pago:
TARJETA ONLINE 21,00
Total a pagar: 21,00
Entregado: 21,00
Devuelto: 0,00
Desglose de IVA... Base Imp. Total IVA
..........IVA - 21% 17,36 3,64
''');
      expect(result, hasLength(5));
      expect(result[0].descripcion, 'CALABAZA LUMINOSA G');
      expect(result[0].precioTotal, 8.00);
      expect(result[1].descripcion, 'BOLSA DE PAPEL. PEQ');
      expect(result[1].precioTotal, 0.50);
      expect(result[2].descripcion, 'SELLOS. 9 UDS');
      expect(result[2].precioTotal, 3.50);
      expect(result[3].descripcion, 'DIADEMA CUMPLEAÑOS');
      expect(result[3].precioTotal, 2.00);
      expect(result[4].descripcion, 'PLANIFICADOR DE EST');
      expect(result[4].precioTotal, 7.00);
      final total = result.fold<double>(0, (sum, i) => sum + (i.precioTotal ?? 0));
      expect(total, closeTo(21.00, 0.001));
    });

    test('no corta por productos que llevan "TOTAL" en medio del nombre', () {
      final result = parseReceiptLines('''
COLGATE TOTAL PROTECCION   3,15
DESODORANTE TOTAL 48H   2,20
TOTAL   5,35
''');
      expect(result, hasLength(2));
      expect(result[0].descripcion, 'COLGATE TOTAL PROTECCION');
      expect(result[0].precioTotal, 3.15);
      expect(result[1].descripcion, 'DESODORANTE TOTAL 48H');
      expect(result[1].precioTotal, 2.20);
    });

    test('no corta por un "TOTAL" suelto sin importe (cabecera de tabla mal separada por el OCR)', () {
      // Caso real: el OCR separó "...DESCRIPCION TOTAL" en dos líneas, y la
      // segunda quedó como un "TOTAL" suelto sin precio, antes de cualquier
      // producto. No debe cortar la lectura del ticket; el "TOTAL" suelto se
      // queda como una línea sin precio más (el usuario la borra a mano),
      // pero los productos de después se siguen leyendo.
      final result = parseReceiptLines('''
TOTAL
UNID CODIGO DESCRIPCION
CALABAZA LUMINOSA G 8,00
BOLSA DE PAPEL. PEQ 0,50
''');
      expect(result.map((r) => r.descripcion), containsAll(['CALABAZA LUMINOSA G', 'BOLSA DE PAPEL. PEQ']));
      final calabaza = result.firstWhere((r) => r.descripcion == 'CALABAZA LUMINOSA G');
      expect(calabaza.precioTotal, 8.00);
      final bolsa = result.firstWhere((r) => r.descripcion == 'BOLSA DE PAPEL. PEQ');
      expect(bolsa.precioTotal, 0.50);
    });

    test('reconoce "Formas de pago" como fin del ticket aunque el OCR meta un espacio suelto', () {
      final result = parseReceiptLines('''
CALABAZA LUMINOSA G 8,00
Formas de p ago:
STA ONLINE 21,00
a pagar: 21,00
''');
      expect(result, hasLength(1));
      expect(result[0].descripcion, 'CALABAZA LUMINOSA G');
    });

    test('formato tabular sin la cantidad inicial (el OCR se la come)', () {
      final result = parseReceiptLines('3073611 CALABAZA LUMINOSA G 8,00');
      expect(result, hasLength(1));
      expect(result.first.descripcion, 'CALABAZA LUMINOSA G');
      expect(result.first.precioTotal, 8.00);
    });

    test('no inventa un producto con el peso huerfano como nombre (no duplica el importe)', () {
      // Caso real: cuando la línea de arriba ya tiene su propio precio (p.ej.
      // "LANGOSTINO COCIDO GORDO   27,14€"), una línea de peso suelta que
      // venga después ("1,940 Kg x 13,99€/Kg") ya no encuentra a quién
      // fusionarse. Antes se colaba como un producto propio (duplicando el
      // importe); ahora se descarta en vez de inventar un nombre falso.
      final result = parseReceiptLines('''
LANGOSTINO COCIDO GORDO   27,14€
1,940 Kg x 13,99€/Kg   A
CEBOLLA DULCE   4,95€
''');
      expect(result, hasLength(2));
      expect(result[0].descripcion, 'LANGOSTINO COCIDO GORDO');
      expect(result[0].precioTotal, 27.14);
      expect(result[1].descripcion, 'CEBOLLA DULCE');
      expect(result[1].precioTotal, 4.95);
    });

    test('tolera que el OCR lea "E" en vez de "€" antes de /Kg', () {
      final result = parseReceiptLines('CEBOLLA DULCE\n0,495 Kg x 9,99E/Kg   4,95€');
      expect(result, hasLength(1));
      expect(result.first.descripcion, 'CEBOLLA DULCE');
      expect(result.first.precioTotal, 4.95);
      expect(result.first.pesoGramos, closeTo(495, 0.01));
    });

    test('tolera un espacio suelto dentro del precio decimal', () {
      final result = parseReceiptLines('HUMMUS A TASTE OF SOL 200G   1, 19€');
      expect(result, hasLength(1));
      expect(result.first.descripcion, 'HUMMUS A TASTE OF SOL 200G');
      expect(result.first.precioTotal, 1.19);
    });

    test('recupera el fragmento de nombre que se parte en la linea de cantidad/precio', () {
      // Caso real: "LECHE ALIPENDE 1L SEMIDESNA" se queda sin precio, y el
      // final de su nombre ("Se") aparece pegado a la cantidad en la
      // siguiente línea ("Se   6 Un x 0,84€/Un   5,04€"). No debe salir un
      // producto llamado "Se": el nombre completo es el de la línea anterior.
      final result = parseReceiptLines('''
LECHE ALIPENDE 1L SEMIDESNA
Se   6 Un x 0,84€/Un   5,04€
''');
      expect(result, hasLength(6));
      for (final item in result) {
        expect(item.descripcion, 'LECHE ALIPENDE 1L SEMIDESNA');
        expect(item.precioTotal, 0.84);
      }
    });

    test('usa la cantidad de una linea suelta que confirma el mismo total (bolsa 2x0,15)', () {
      // Caso real: "BOLSA PLASTICO RECICLADO   B   0,30€" ya calcula su
      // propio total, y la cantidad real ("2 Un x 0,15€/Un") llega SUELTA
      // justo después. Como el total coincide, se reparte en 2 unidades de
      // 0,15€ en vez de quedarse como una sola línea de 0,30€.
      final result = parseReceiptLines('''
BOLSA PLASTICO RECICLADO   B   0,30€
2 Un x 0,15€/Un
''');
      expect(result, hasLength(2));
      for (final item in result) {
        expect(item.descripcion, 'BOLSA PLASTICO RECICLADO');
        expect(item.precioTotal, 0.15);
      }
    });

    test('no reparte si la linea suelta siguiente no confirma el mismo total', () {
      final result = parseReceiptLines('''
BANANA   0,79€
2 Un x 0,50€/Un
''');
      // 2 x 0,50 = 1,00, no coincide con 0,79: son cosas distintas, no se
      // debe tocar el precio de BANANA ni repartirlo en unidades.
      expect(result, hasLength(1));
      expect(result.first.descripcion, 'BANANA');
      expect(result.first.precioTotal, 0.79);
    });

    test('reconoce el peso aunque el OCR pegue la "x" a "Kg" sin espacio', () {
      final result = parseReceiptLines('''
BANANA
1,195 Kgx 1,49€/Kg   C   1,78€
''');
      expect(result, hasLength(1));
      expect(result.first.descripcion, 'BANANA');
      expect(result.first.precioTotal, 1.78);
      expect(result.first.pesoGramos, closeTo(1195, 0.01));
    });

    test('descarta un peso que no cuadra con el total impreso (digito mal leido por el OCR)', () {
      // 9,360 Kg x 2,99€/Kg darian 27,99€, pero el ticket imprime 1,08€
      // (el peso real era 0,360 Kg: el OCR leyo "0" como "9"). Nos quedamos
      // con el precio impreso, que es fiable, pero no mostramos el peso.
      final result = parseReceiptLines('''
PIMIENTO ROJO LAMUYO
9,360 Kg x 2,99€/Kg   C   1,08€
''');
      expect(result, hasLength(1));
      expect(result.first.descripcion, 'PIMIENTO ROJO LAMUYO');
      expect(result.first.precioTotal, 1.08);
      expect(result.first.pesoGramos, isNull);
    });

    test('tolera un digito de mas justo antes de /Kg (E confundida con un 6)', () {
      final result = parseReceiptLines('''
CALABACIN
0,455 Kg x 1,896/Kg   C   0,86€
''');
      expect(result, hasLength(1));
      expect(result.first.descripcion, 'CALABACIN');
      expect(result.first.precioTotal, 0.86);
      expect(result.first.pesoGramos, closeTo(455, 0.01));
    });

    test('reconoce "Factura" con espacio y digito colados por el OCR', () {
      expect(isNoiseLine('Fac tura simp1ificada:   A/6398 27'), isTrue);
    });

    test('reconoce la razon social con coma en vez de punto (S,LU.)', () {
      expect(isNoiseLine('TIGER STORES SPAIN, S,LU.'), isTrue);
    });

    test('reconoce codigo postal + poblacion separados por coma', () {
      expect(isNoiseLine('C ORENSE, 34, 10, 28020, MADRID'), isTrue);
    });

    test('limpia el codigo de articulo suelto cuando no hay precio detectable', () {
      final result = parseReceiptLines('3055619   SELL0S. 9 UDS');
      expect(result, hasLength(1));
      expect(result.first.descripcion, 'SELL0S. 9 UDS');
      expect(result.first.precioTotal, isNull);
    });

    test('CRITICO: "Factura" en la cabecera (antes de los productos) no corta el resto del ticket', () {
      // "Factura simplificada" es solo ruido de una linea: a diferencia de
      // "Formas de pago" o "TOTAL", puede aparecer en la CABECERA del ticket
      // (como en Flying Tiger), antes de cualquier producto. Si se tratase
      // como fin de ticket, se perderian todos los articulos.
      final result = parseReceiptLines('''
Factura simplificada: A/639827
CALABAZA LUMINOSA G   8,00
BOLSA DE PAPEL. PEQ   0,50
''');
      expect(result, hasLength(2));
      expect(result[0].descripcion, 'CALABAZA LUMINOSA G');
      expect(result[1].descripcion, 'BOLSA DE PAPEL. PEQ');
    });

    test('deja el precio nulo si no se detecta ninguno', () {
      final result = parseReceiptLines('PRODUCTO SIN PRECIO LEGIBLE');
      expect(result, hasLength(1));
      expect(result.first.precioTotal, isNull);
    });
  });
}
