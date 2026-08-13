import 'package:flutter/material.dart';

import '../api/dto.dart';
import '../app.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/qr_scanner.dart';
import '../widgets/ui.dart';

/// Paso 8 — «Estoy aquí»: identificar el surtidor por QR o número.
class ArrivalScreen extends StatefulWidget {
  const ArrivalScreen({super.key});

  @override
  State<ArrivalScreen> createState() => _ArrivalScreenState();
}

class _ArrivalScreenState extends State<ArrivalScreen> {
  int? _pump;
  String? _qrToken;
  bool _scanning = false;
  bool _sending = false;
  List<PumpStatus> _live = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPumps());
  }

  Future<void> _refreshPumps() async {
    if (!mounted) return;
    final list = await AppScope.read(context).loadPumps();
    if (!mounted || list.isEmpty) return;
    setState(() => _live = list);
  }

  /// El QR del surtidor lleva el `qr_token` del broker; si además trae el
  /// número (…/pump/3) lo usamos para pintar la selección.
  static int? _pumpFromQr(String raw) {
    final m = RegExp(r'(?:pump|surtidor|p)[^0-9]{0,3}(\d{1,2})', caseSensitive: false).firstMatch(raw);
    if (m != null) return int.tryParse(m.group(1)!);
    final only = RegExp(r'^\s*(\d{1,2})\s*$').firstMatch(raw);
    return only == null ? null : int.tryParse(only.group(1)!);
  }

  Future<void> _scan() async {
    final code = await QrScanSheet.open(context);
    if (code == null || !mounted) return;
    setState(() {
      _qrToken = code;
      _scanning = true;
      _pump = _pumpFromQr(code) ?? _pump;
    });
  }

  bool _busy(int n) {
    if (_live.isEmpty) return n == 2 || n == 6;
    final p = _live.where((e) => e.number == n).toList();
    return p.isEmpty ? false : p.first.busy;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final pumps = _live.isNotEmpty ? _live.length : (s.station?.pumps ?? 8);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            OHeader(
              title: 'Estoy aquí',
              step: 'Paso 2 de 4 · llegada',
              subtitle: 'Escanea el QR del surtidor o escoge el número.',
              onBack: () => Navigator.pop(context),
              action: OPill(s.orderCode.isEmpty ? 'ORDEN' : s.orderCode, color: C.green),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: OStepper(current: 1),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GestureDetector(
                      onTap: _scan,
                      child: Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: C.inkDeep,
                          borderRadius: Radii.card,
                          border: Border.all(color: _scanning ? C.green : C.line),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              _scanning ? Icons.check_circle_outline : Icons.qr_code_scanner,
                              size: 56,
                              color: _scanning ? C.green : C.mutedDim,
                            ),
                            Positioned(
                              bottom: 18,
                              child: Text(
                                _scanning
                                    ? (_pump == null ? 'Surtidor identificado' : 'Surtidor $_pump detectado')
                                    : 'Toca para escanear el QR',
                                style: body(
                                  size: 13,
                                  color: _scanning ? C.green : C.muted,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Gap.h24,
                    Row(
                      children: [
                        Expanded(child: Container(height: 1, color: C.line)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: OLabel('o escoge el número'),
                        ),
                        Expanded(child: Container(height: 1, color: C.line)),
                      ],
                    ),
                    Gap.h16,
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.15,
                      ),
                      itemCount: pumps,
                      itemBuilder: (_, i) {
                        final n = i + 1;
                        final sel = _pump == n;
                        final busy = _busy(n);
                        return GestureDetector(
                          onTap: busy
                              ? null
                              : () => setState(() {
                                    _pump = n;
                                    _qrToken = null;
                                    _scanning = false;
                                  }),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: sel ? C.green.withOpacity(0.16) : C.surface,
                              borderRadius: Radii.field,
                              border: Border.all(color: sel ? C.green : C.line),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('$n',
                                    style: display(
                                        size: 20,
                                        color: busy ? C.mutedDim : (sel ? C.green : C.bone),
                                        weight: FontWeight.w700)),
                                if (busy)
                                  Text('ocupado', style: mono(size: 8, color: C.mutedDim)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    Gap.h24,
                    OCard(
                      child: Row(
                        children: [
                          const Icon(Icons.directions_car_filled_outlined, size: 20, color: C.green),
                          Gap.w12,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${s.vehicle.make} · ${s.vehicle.color}',
                                    style: body(size: 13, weight: FontWeight.w600)),
                                Gap.h4,
                                Text('Tablilla ${s.vehicle.plate} · el empleado te identifica por foto',
                                    style: body(size: 11, color: C.mutedDim)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: OButton(
                label: _sending
                    ? 'Avisando…'
                    : (_pump == null && _qrToken == null
                        ? 'Selecciona el surtidor'
                        : 'Avisar que llegué · surtidor ${_pump ?? 'QR'}'),
                onTap: (_pump == null && _qrToken == null) || _sending
                    ? null
                    : () async {
                        setState(() => _sending = true);
                        final ok = await s.arrive(pump: _pump, qrToken: _qrToken);
                        if (!context.mounted) return;
                        if (!ok) {
                          setState(() => _sending = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(s.error ?? 'El surtidor no aceptó la autorización')),
                          );
                          return;
                        }
                        Navigator.pushReplacementNamed(context, Routes.dispensing);
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
