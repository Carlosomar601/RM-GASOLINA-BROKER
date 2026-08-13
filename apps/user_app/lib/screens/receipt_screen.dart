import 'package:flutter/material.dart';

import '../app.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/ui.dart';

/// Paso 10 — recibo y liberación de la retención.
class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final when = s.authorizedAt ?? DateTime.now();
    final stamp =
        '${when.day.toString().padLeft(2, '0')}/${when.month.toString().padLeft(2, '0')}/${when.year} · '
        '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            OHeader(
              title: 'Recibo',
              step: 'Paso 4 de 4 · liquidado',
              subtitle: stamp,
              action: OPill('PAGADO', color: C.green, filled: true),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: OStepper(current: 3),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OCard(
                      color: C.inkDeep,
                      accent: C.green,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OLabel('Cobrado'),
                          Gap.h8,
                          OMoney(s.finalTotal, size: 42, color: C.green),
                          Gap.h8,
                          Text('Retención liberada: \$${s.releasedHold.toStringAsFixed(2)}',
                              style: body(size: 12, color: C.amber)),
                        ],
                      ),
                    ),
                    Gap.h16,
                    OCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OLabel('Detalle'),
                          Gap.h8,
                          ORow(
                            '${s.fuelType.label} · ${s.dispensedLiters.toStringAsFixed(2)} L',
                            '\$${s.dispensedAmount.toStringAsFixed(2)}',
                          ),
                          ...s.cart.map((l) =>
                              ORow('${l.qty}× ${l.product.name}', '\$${l.total.toStringAsFixed(2)}')),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Container(height: 1, color: C.line),
                          ),
                          ORow('Total', '\$${s.finalTotal.toStringAsFixed(2)}', strong: true),
                        ],
                      ),
                    ),
                    Gap.h16,
                    OCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OLabel('Trazabilidad'),
                          Gap.h8,
                          ORow('Orden', s.orderCode.isEmpty ? '—' : s.orderCode),
                          ORow('Estación', s.station?.name ?? '—'),
                          ORow('Surtidor', '#${s.pumpNumber ?? '—'}'),
                          ORow('Tarjeta', '•••• ${s.cardLast4}'),
                          Gap.h8,
                          OLabel('edge_transaction_uuid'),
                          Gap.h4,
                          Text(
                            s.edgeTxUuid.isEmpty ? '—' : s.edgeTxUuid,
                            style: mono(size: 11, color: C.muted),
                          ),
                        ],
                      ),
                    ),
                    Gap.h16,
                    Row(
                      children: [
                        Expanded(
                          child: OButton(
                            label: 'Enviar por correo',
                            variant: OButtonVariant.ghost,
                            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: C.surfaceHi,
                                content: Text('Recibo enviado a ${s.email}',
                                    style: body(size: 13, color: C.bone)),
                              ),
                            ),
                          ),
                        ),
                        Gap.w12,
                        Expanded(
                          child: OButton(
                            label: 'Calificar',
                            variant: OButtonVariant.ghost,
                            icon: Icons.star_outline,
                            onTap: () {},
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: OButton(
                label: 'Listo',
                onTap: () {
                  s.resetOrder();
                  Navigator.pushNamedAndRemoveUntil(context, Routes.stations, (r) => false);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
