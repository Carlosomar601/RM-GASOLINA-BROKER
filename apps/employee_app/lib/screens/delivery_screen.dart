import 'package:flutter/material.dart';

import '../app.dart';
import '../models/models.dart';
import '../state/shift_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/ui.dart';

/// 5 · Entrega en el carro: confirmar identidad por foto, surtir y cerrar.
class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  bool _identityOk = false;
  bool _fuelDone = false;
  double _dispensed = 0;

  @override
  Widget build(BuildContext context) {
    final s = ShiftScope.of(context);
    final t = s.active ?? s.tasks.first;
    if (_dispensed == 0) _dispensed = t.dispensed > 0 ? t.dispensed : t.cap;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ShiftBar(),
            OHeader(
              title: 'Entrega',
              step: '${t.code} · surtidor ${t.pump ?? '—'}',
              onBack: () => Navigator.pop(context),
              action: OPill(t.status.label.toUpperCase(), color: t.status.color),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                children: [
                  OCard(
                    accent: _identityOk ? C.green : C.amber,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            OLabel('Paso 1 · confirmar identidad'),
                            if (_identityOk) OPill('OK', color: C.green, filled: true),
                          ],
                        ),
                        Gap.h12,
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  Container(
                                    height: 108,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: C.surfaceHi,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: C.line),
                                    ),
                                    child: const Icon(Icons.person_outline,
                                        size: 34, color: C.mutedDim),
                                  ),
                                  Gap.h8,
                                  Text('Foto en cuenta', style: mono(size: 9, color: C.mutedDim)),
                                ],
                              ),
                            ),
                            Gap.w12,
                            Expanded(
                              child: Column(
                                children: [
                                  Container(
                                    height: 108,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: C.surfaceHi,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: C.line),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.directions_car_filled_outlined,
                                            size: 26, color: C.green),
                                        Gap.h4,
                                        Text(t.plate,
                                            style: mono(size: 12, color: C.bone, weight: FontWeight.w700)),
                                      ],
                                    ),
                                  ),
                                  Gap.h8,
                                  Text('Vehículo en pista', style: mono(size: 9, color: C.mutedDim)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Gap.h12,
                        Text('${t.customer} · ${t.vehicle}',
                            style: body(size: 13, weight: FontWeight.w600)),
                        Gap.h12,
                        if (!_identityOk)
                          Row(
                            children: [
                              Expanded(
                                child: OButton(
                                  label: 'No coincide',
                                  variant: OButtonVariant.danger,
                                  onTap: () => showDialog<void>(
                                    context: context,
                                    builder: (_) => _mismatchDialog(context),
                                  ),
                                ),
                              ),
                              Gap.w12,
                              Expanded(
                                flex: 2,
                                child: OButton(
                                  label: 'Coincide',
                                  onTap: () async {
                                    final ok = await s.verifyIdentity(t, matches: true);
                                    if (!context.mounted) return;
                                    if (!ok) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(s.error ?? 'No se pudo registrar la verificación')),
                                      );
                                      return;
                                    }
                                    setState(() => _identityOk = true);
                                  },
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  Gap.h12,
                  Opacity(
                    opacity: _identityOk ? 1 : 0.45,
                    child: OCard(
                      accent: _fuelDone ? C.green : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OLabel('Paso 2 · surtir combustible'),
                          Gap.h12,
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('\$${_dispensed.toStringAsFixed(2)}',
                                  style: mono(size: 34, color: t.grade.color, weight: FontWeight.w600)),
                              Gap.w12,
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text('de \$${t.cap.toStringAsFixed(2)} · ${t.grade.label}',
                                    style: mono(size: 11, color: C.mutedDim)),
                              ),
                            ],
                          ),
                          Slider(
                            value: _dispensed.clamp(0.0, t.cap).toDouble(),
                            max: t.cap,
                            onChanged: _identityOk && !_fuelDone
                                ? (v) => setState(() => _dispensed = v)
                                : null,
                          ),
                          Text('El monto real llega del surtidor; el deslizador es solo para la demo.',
                              style: body(size: 11, color: C.mutedDim)),
                          Gap.h12,
                          OButton(
                            label: _fuelDone ? 'Surtido cerrado' : 'Cerrar surtido',
                            variant: _fuelDone ? OButtonVariant.ghost : OButtonVariant.primary,
                            onTap: _identityOk && !_fuelDone
                                ? () => setState(() => _fuelDone = true)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Gap.h12,
                  if (t.items.isNotEmpty)
                    Opacity(
                      opacity: _fuelDone ? 1 : 0.45,
                      child: OCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OLabel('Paso 3 · entregar ${t.items.length} artículo(s)'),
                            Gap.h8,
                            ...t.items.map((i) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Icon(i.picked ? Icons.check_circle : Icons.circle_outlined,
                                          size: 16, color: i.picked ? C.green : C.mutedDim),
                                      Gap.w8,
                                      Expanded(child: Text('${i.qty}× ${i.name}', style: body(size: 13))),
                                    ],
                                  ),
                                )),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: OButton(
                label: 'Completar orden · \$${(_dispensed + t.itemsTotal).toStringAsFixed(2)}',
                onTap: _fuelDone
                    ? () async {
                        final ok = await s.close(t, dispensed: _dispensed);
                        if (!context.mounted) return;
                        if (!ok) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(s.error ?? 'El broker rechazó el cierre')),
                          );
                          return;
                        }
                        Navigator.pushNamedAndRemoveUntil(context, Routes.dashboard, (r) => false);
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mismatchDialog(BuildContext context) => Dialog(
        backgroundColor: C.surface,
        shape: const RoundedRectangleBorder(borderRadius: Radii.card),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Identidad no coincide', style: display(size: 19)),
              Gap.h8,
              Text(
                'No entregues. La orden queda en revisión y el supervisor recibe el aviso con la foto y la tablilla.',
                style: body(size: 13, color: C.muted),
              ),
              Gap.h16,
              OButton(
                label: 'Notificar supervisor',
                variant: OButtonVariant.danger,
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );
}
