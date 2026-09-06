import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// El correo y la contraseña guardados en el móvil para no tener que
/// teclearlos cada vez que se entra.
///
/// Van en el almacén seguro del sistema (en Android, respaldado por el
/// Keystore), no en unas preferencias normales: una contraseña en texto plano
/// la puede leer cualquier copia de seguridad o cualquier móvil rooteado.
class SavedCredentials {
  static const _almacen = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _claveCorreo = 'login_email';
  static const _clavePassword = 'login_password';

  static Future<({String correo, String password})?> cargar() async {
    try {
      final correo = await _almacen.read(key: _claveCorreo);
      final password = await _almacen.read(key: _clavePassword);
      if (correo == null || password == null) return null;
      return (correo: correo, password: password);
    } catch (_) {
      // Si el almacén no se puede abrir (una restauración de copia de
      // seguridad puede dejar las claves ilegibles), se entra a mano y ya.
      return null;
    }
  }

  static Future<void> guardar({required String correo, required String password}) async {
    try {
      await _almacen.write(key: _claveCorreo, value: correo);
      await _almacen.write(key: _clavePassword, value: password);
    } catch (_) {
      // Guardar es una comodidad: si falla, no se le estropea la entrada a
      // nadie por eso.
    }
  }

  static Future<void> borrar() async {
    try {
      await _almacen.delete(key: _claveCorreo);
      await _almacen.delete(key: _clavePassword);
    } catch (_) {
      // Nada que hacer: si no se puede borrar, tampoco se puede avisar de
      // forma útil desde aquí.
    }
  }
}
