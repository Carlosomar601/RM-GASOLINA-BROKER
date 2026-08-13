/// Configuración del enlace con el broker Octano.
///
/// La URL base se inyecta al compilar, no se hornea en el binario:
///
///   flutter run --dart-define=OCTANO_API=http://192.168.100.20:8080
///
/// Sin `OCTANO_API` la app arranca en modo demo (datos locales), que es como
/// se presentan los mockups.
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment('OCTANO_API');

  /// Estación por defecto para saltar el selector en pruebas de campo.
  static const String defaultStationId = String.fromEnvironment('OCTANO_STATION');

  /// Segundos entre sondeos de respaldo cuando el WebSocket no está vivo.
  static const int pollSeconds = int.fromEnvironment('OCTANO_POLL', defaultValue: 3);

  static bool get live => baseUrl.trim().isNotEmpty;

  static Uri rest(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse(baseUrl.trim());
    return base.replace(
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}$path',
      queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
    );
  }

  /// ws(s)://host/v1/stream?token=…
  static Uri stream(String token) {
    final base = Uri.parse(baseUrl.trim());
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}/v1/stream',
      queryParameters: {'token': token},
    );
  }
}
