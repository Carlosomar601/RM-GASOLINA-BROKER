import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_config.dart';

/// Evento de estación del broker: `task_incoming`, `task_updated`,
/// `order_updated`. El handheld sólo necesita saber que algo cambió para
/// refrescar la cola.
class StationEvent {
  const StationEvent(this.type, this.payload);
  final String type;
  final Map<String, dynamic> payload;

  String? get taskId => payload['taskId'] as String?;
  String? get status => payload['status'] as String?;
  bool get isNewTask => type == 'task_incoming';
}

/// Suscripción a la estación del turno. El broker suscribe solo al empleado
/// al conectar; igual mandamos el `subscribe` explícito por si el token
/// cambia de estación.
class StationStream {
  StationStream({required this.token, required this.stationId, required this.onEvent, this.onStatus});

  final String token;
  final String stationId;
  final void Function(StationEvent) onEvent;
  final void Function(bool connected)? onStatus;

  WebSocketChannel? _ch;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  int _attempt = 0;
  bool _closed = false;

  void connect() {
    if (_closed) return;
    try {
      final ch = WebSocketChannel.connect(ApiConfig.stream(token));
      _ch = ch;
      ch.sink.add(jsonEncode({'subscribe': 'station', 'id': stationId}));
      onStatus?.call(true);
      _attempt = 0;
      _sub = ch.stream.listen(
        (msg) {
          try {
            final j = jsonDecode('$msg');
            if (j is! Map<String, dynamic> || j['scope'] != 'station') return;
            final payload = (j['payload'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
            onEvent(StationEvent('${j['type']}', payload));
          } catch (_) {/* ignora mensajes no JSON */}
        },
        onDone: _scheduleRetry,
        onError: (_) => _scheduleRetry(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    onStatus?.call(false);
    if (_closed) return;
    _sub?.cancel();
    _sub = null;
    _ch = null;
    _attempt = (_attempt + 1).clamp(1, 6);
    _retry?.cancel();
    _retry = Timer(Duration(seconds: 1 << (_attempt - 1)), connect);
  }

  void close() {
    _closed = true;
    _retry?.cancel();
    _sub?.cancel();
    _ch?.sink.close();
    _ch = null;
  }
}
