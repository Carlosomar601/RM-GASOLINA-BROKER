import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Error normalizado del broker. El backend responde siempre
/// `{ error, message }`, así que la app puede mostrar `message` directamente.
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  bool get isAuth => status == 401;
  bool get isOffline => status == 0;
  bool get isConflict => status == 409;

  @override
  String toString() => 'ApiException($status/$code): $message';
}

/// Cliente HTTP mínimo: token bearer, timeouts y decodificación de errores.
class ApiClient {
  ApiClient({http.Client? inner}) : _http = inner ?? http.Client();

  final http.Client _http;
  static const _timeout = Duration(seconds: 15);

  String? token;

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        'accept': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      };

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _http.get(ApiConfig.rest(path, query), headers: _headers));

  Future<dynamic> post(String path, {Object? body}) => _send(
        () => _http.post(
          ApiConfig.rest(path),
          headers: _headers,
          body: jsonEncode(body ?? const <String, dynamic>{}),
        ),
      );

  Future<dynamic> _send(Future<http.Response> Function() run) async {
    late http.Response res;
    try {
      res = await run().timeout(_timeout);
    } on TimeoutException {
      throw ApiException(0, 'timeout', 'El broker no respondió a tiempo.');
    } on SocketException catch (e) {
      throw ApiException(0, 'network', 'Sin conexión con el broker (${e.osError?.message ?? 'red'}).');
    } catch (e) {
      throw ApiException(0, 'network', 'No se pudo contactar el broker: $e');
    }

    final text = res.body.isEmpty ? '{}' : res.body;
    dynamic parsed;
    try {
      parsed = jsonDecode(text);
    } catch (_) {
      if (res.statusCode >= 400) {
        throw ApiException(res.statusCode, 'bad_response', text.length > 200 ? text.substring(0, 200) : text);
      }
      return null;
    }

    if (res.statusCode >= 400) {
      final map = parsed is Map<String, dynamic> ? parsed : const <String, dynamic>{};
      throw ApiException(
        res.statusCode,
        '${map['error'] ?? 'error'}',
        '${map['message'] ?? map['detail'] ?? _fallbackMessage(res.statusCode, '${map['error'] ?? ''}')}',
      );
    }
    return parsed;
  }

  static String _fallbackMessage(int status, String code) => switch (code) {
        'invalid_credentials' => 'Teléfono o contraseña incorrectos.',
        'phone_taken' => 'Ese teléfono ya tiene cuenta.',
        'pump_not_found' => 'No encontramos ese surtidor en la estación.',
        'hose_not_mapped' => 'Ese surtidor no despacha el grado escogido.',
        'pump_authorize_failed' => 'El controlador rechazó la autorización.',
        'no_price' => 'La estación no tiene precio vigente para ese grado.',
        'bad_state' => 'La orden ya no está en ese estado.',
        _ => 'Error del broker ($status).',
      };

  void close() => _http.close();
}
