import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../data/mock_data.dart';
import '../services/speech_service.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/ui.dart';

/// Paso 5 — compra por voz. La demo simula el dictado y muestra la
/// interpretación antes de aplicarla a la orden.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  final SpeechService _speech = SpeechService();
  bool _listening = false;
  bool _simulated = false;
  String _transcript = '';
  VoiceParse? _parse;
  Timer? _t;
  int _sample = 0;

  @override
  void dispose() {
    _t?.cancel();
    _speech.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// Micrófono real si el equipo lo tiene; si no, dictado simulado para que
  /// la pantalla siga siendo demostrable en escritorio o emulador.
  Future<void> _listen() async {
    if (_listening) {
      await _stop();
      return;
    }
    setState(() {
      _listening = true;
      _transcript = '';
      _parse = null;
    });

    final ready = await _speech.ensureReady();
    if (!mounted) return;
    if (!ready) {
      setState(() => _simulated = true);
      _simulate();
      return;
    }
    setState(() => _simulated = false);
    await _speech.listen(
      onText: (text, isFinal) {
        if (!mounted) return;
        setState(() => _transcript = text);
        if (isFinal) _finish();
      },
    );
  }

  Future<void> _stop() async {
    _t?.cancel();
    await _speech.stop();
    if (mounted) _finish();
  }

  void _finish() {
    if (!mounted) return;
    setState(() {
      _listening = false;
      _parse = _transcript.trim().isEmpty ? null : AppScope.of(context).parseVoice(_transcript);
    });
  }

  void _simulate() {
    final phrase = MockData.voiceSamples[_sample % MockData.voiceSamples.length];
    _sample++;
    var i = 0;
    _t?.cancel();
    _t = Timer.periodic(const Duration(milliseconds: 45), (t) {
      if (i >= phrase.length) {
        t.cancel();
        _finish();
        return;
      }
      i++;
      setState(() => _transcript = phrase.substring(0, i));
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final parse = _parse;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            OHeader(
              title: 'Compra por voz',
              step: 'Manos libres',
              subtitle: 'Dicta combustible y artículos en una sola frase.',
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GestureDetector(
                      onTap: _listen,
                      child: AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, __) {
                          final v = _listening ? _pulse.value : 0.0;
                          return Container(
                            height: 190,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: C.surface,
                              borderRadius: Radii.card,
                              border: Border.all(
                                color: _listening
                                    ? C.amber.withOpacity(0.35 + v * 0.5)
                                    : C.line,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 74 + v * 10,
                                  height: 74 + v * 10,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: (_listening ? C.amber : C.green).withOpacity(0.14),
                                    borderRadius: Radii.pill,
                                  ),
                                  child: Icon(_listening ? Icons.graphic_eq : Icons.mic_none,
                                      size: 32, color: _listening ? C.amber : C.green),
                                ),
                                Gap.h16,
                                Text(
                                  _listening
                                      ? (_simulated ? 'Escuchando… (demo)' : 'Escuchando… toca para terminar')
                                      : 'Toca para hablar',
                                  style: body(size: 14, color: C.muted, weight: FontWeight.w600),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Gap.h16,
                    if (_transcript.isNotEmpty)
                      OCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OLabel('Transcripción'),
                            Gap.h8,
                            Text('«$_transcript»',
                                style: body(size: 16, height: 1.35, weight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    if (parse != null && !parse.isEmpty) ...[
                      Gap.h16,
                      OCard(
                        accent: C.green,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                OLabel('Interpretación'),
                                OPill('LISTA', color: C.green),
                              ],
                            ),
                            Gap.h12,
                            if (parse.amount != null)
                              ORow('Combustible',
                                  '\$${parse.amount!.toStringAsFixed(0)} · ${(parse.fuelType ?? s.fuelType).label}'),
                            ...parse.products.map(
                              (p) => ORow(p.name, '\$${p.price.toStringAsFixed(2)}'),
                            ),
                            Gap.h12,
                            OButton(
                              label: 'Aplicar a mi orden',
                              onTap: () {
                                s.applyVoice(parse);
                                Navigator.pushReplacementNamed(context, Routes.fuel);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    Gap.h24,
                    OLabel('Puedes decir'),
                    Gap.h12,
                    ...MockData.voiceSamples.map(
                      (v) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OCard(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Text('«$v»', style: body(size: 13, color: C.muted)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
