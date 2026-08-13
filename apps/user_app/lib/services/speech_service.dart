import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Dictado. Usa el reconocedor del sistema (es-PR / es-US) y, si el equipo no
/// tiene micrófono o permiso —escritorio, emulador, demo— cae a una frase
/// escrita letra por letra para que la pantalla siga siendo demostrable.
class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _ready = false;
  bool _unavailable = false;

  bool get listening = _speech.isListening;

  /// true si hay reconocedor real disponible en este equipo.
  Future<bool> ensureReady() async {
    if (_ready) return true;
    if (_unavailable) return false;
    try {
      _ready = await _speech.initialize(
        onError: (_) {},
        onStatus: (_) {},
        debugLogging: false,
      );
    } catch (_) {
      _ready = false;
    }
    _unavailable = !_ready;
    return _ready;
  }

  /// Escucha en español; emite parciales para que la transcripción se vea
  /// crecer igual que en la demo.
  Future<void> listen({
    required void Function(String text, bool finalResult) onText,
    Duration listenFor = const Duration(seconds: 15),
  }) async {
    if (!await ensureReady()) return;
    final locales = await _speech.locales();
    final es = locales
        .where((l) => l.localeId.toLowerCase().startsWith('es'))
        .toList();
    final preferred = es
            .where((l) => l.localeId.toLowerCase().contains('pr') || l.localeId.toLowerCase().contains('us'))
            .firstOrNull ??
        es.firstOrNull;

    await _speech.listen(
      onResult: (r) => onText(r.recognizedWords, r.finalResult),
      listenFor: listenFor,
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      localeId: preferred?.localeId,
      cancelOnError: true,
    );
  }

  Future<void> stop() async {
    if (_speech.isListening) await _speech.stop();
  }

  void dispose() {
    if (_speech.isListening) _speech.cancel();
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
