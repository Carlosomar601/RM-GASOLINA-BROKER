import 'package:shared_preferences/shared_preferences.dart';

/// Sesión del turno guardada en el handheld: token, empleado y estación.
/// El PIN nunca se guarda.
class SessionStore {
  SessionStore._();

  static const _kToken = 'octano.emp.token';
  static const _kEmployee = 'octano.emp.id';
  static const _kStation = 'octano.emp.station';
  static const _kRole = 'octano.emp.role';
  static const _kExpires = 'octano.emp.expiresAt';

  static Future<void> save({
    required String token,
    required String employeeId,
    required String stationId,
    required String role,
    DateTime? expiresAt,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kToken, token);
    await p.setString(_kEmployee, employeeId);
    await p.setString(_kStation, stationId);
    await p.setString(_kRole, role);
    if (expiresAt != null) await p.setString(_kExpires, expiresAt.toIso8601String());
  }

  static Future<({String token, String employeeId, String stationId, String role})?> read() async {
    final p = await SharedPreferences.getInstance();
    final token = p.getString(_kToken);
    final employeeId = p.getString(_kEmployee);
    final stationId = p.getString(_kStation);
    if (token == null || token.isEmpty || employeeId == null || stationId == null) return null;
    final exp = DateTime.tryParse(p.getString(_kExpires) ?? '');
    if (exp != null && exp.isBefore(DateTime.now())) {
      await clear();
      return null;
    }
    return (token: token, employeeId: employeeId, stationId: stationId, role: p.getString(_kRole) ?? 'attendant');
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    for (final k in [_kToken, _kEmployee, _kStation, _kRole, _kExpires]) {
      await p.remove(k);
    }
  }
}
