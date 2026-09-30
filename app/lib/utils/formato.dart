/// Un número con el formato de aquí: coma para los decimales y punto para los
/// miles, "1.977,02".
///
/// A mano y no con `intl`: es lo único que hace falta de todo el paquete, y
/// así no hay que arrastrar una dependencia ni inicializar locales.
String numeroEs(double valor, {int decimales = 2}) {
  // Se redondea antes de mirar el signo: un -0,001 a dos decimales es cero, y
  // "-0,00" no es algo que nadie quiera leer.
  final redondeado = double.parse(valor.toStringAsFixed(decimales));
  final partes = redondeado.abs().toStringAsFixed(decimales).split('.');
  final enteros = partes[0];

  final buffer = StringBuffer();
  for (var i = 0; i < enteros.length; i++) {
    if (i > 0 && (enteros.length - i) % 3 == 0) buffer.write('.');
    buffer.write(enteros[i]);
  }
  if (partes.length > 1) {
    buffer.write(',');
    buffer.write(partes[1]);
  }

  return redondeado < 0 ? '-$buffer' : buffer.toString();
}

/// Un importe, "1.977,02 €". Con [conSigno], los positivos llevan un '+'
/// delante (para un balance, donde importa de qué lado está).
String euros(double valor, {bool conSigno = false, int decimales = 2}) {
  final signo = conSigno && double.parse(valor.toStringAsFixed(decimales)) > 0 ? '+' : '';
  return '$signo${numeroEs(valor, decimales: decimales)} €';
}

/// Un peso, en la unidad que se lea mejor: "1,20 kg" a partir del kilo, y
/// "850 g" por debajo.
String pesoLegible(double gramos) =>
    gramos >= 1000 ? '${numeroEs(gramos / 1000)} kg' : '${numeroEs(gramos, decimales: 0)} g';
