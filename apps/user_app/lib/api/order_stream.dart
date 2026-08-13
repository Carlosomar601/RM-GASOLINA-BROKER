import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_config.dart';

/// Evento del bus de tiempo real del broker.
/// `{ scope, orderId, type, payload, at }`
class StreamEvent {
  const StreamEvent(this.type, this.payload);
  final String type;
  final Map<String, dynamic> payload;

  double? get amount => (payload['amount'] as num?)?.toDouble();
  double? get volume => (payload['volume'] as num?)?.toDouble();
  String? get status => payload['status'] as String?;
}

/// Suscripción al ciclo de vida de UNA orden. Reconecta con retroceso
/// exponencial; el sondeo HTTP del AppState cubre los huecos.
class OrderStream {
  OrderStream({required this.token, required this.orderId, required this.onEvent, this.onStatus});

  final String token;
  final String orderId;
  final void Function(StreamEvent) onEvent;
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
      ch.sink.add(jsonEncode({'subscribe': 'order', 'id': orderId}));
      onStatus?.call(true);
      _attempt = 0;
      _sub = ch.stream.listen(
        (msg) {
          try {
            final j = jsonDecode('$msg');
            if (j is! Map<String, dynamic>) return;
            if (j['scope'] != 'order' || j['orderId'] != orderId) return;
            final payload = (j['payload'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
            onEvent(StreamEvent('${j['type']}', payload));
          } catch (_) {/* mensaje no JSON: se ignora */}
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
