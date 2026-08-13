import 'package:shared_preferences/shared_preferences.dart';

/// Sesión guardada entre arranques. Guarda sólo el token y el id del cliente;
/// nada de datos de tarjeta.
class SessionStore {
  SessionStore._();

  static const _kToken = 'octano.token';
  static const _kCustomer = 'octano.customerId';
  static const _kExpires = 'octano.expiresAt';

  static Future<void> save({required String token, required String customerId, DateTime? expiresAt}) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kToken, token);
    await p.setString(_kCustomer, customerId);
    if (expiresAt != null) await p.setString(_kExpires, expiresAt.toIso8601String());
  }

  static Future<({String token, String customerId})?> read() async {
    final p = await SharedPreferences.getInstance();
    final token = p.getString(_kToken);
    final customer = p.getString(_kCustomer);
    if (token == null || token.isEmpty || customer == null) return null;
    final exp = DateTime.tryParse(p.getString(_kExpires) ?? '');
    if (exp != null && exp.isBefore(DateTime.now())) {
      await clear();
      return null;
    }
    return (token: token, customerId: customer);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kCustomer);
    await p.remove(_kExpires);
  }
}
