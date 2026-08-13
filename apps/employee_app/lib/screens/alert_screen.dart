import 'package:flutter/material.dart';

import '../app.dart';
import '../models/models.dart';
import '../state/shift_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/ui.dart';

/// 3 · Alerta de llegada: el cliente dijo «estoy aquí» en el surtidor.
class AlertScreen extends StatelessWidget {
  const AlertScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = ShiftScope.of(context);
    final t = s.active ?? (s.incoming.isNotEmpty ? s.incoming.first : s.tasks.first);

    return Scaffold(
      backgroundColor: C.inkDeep,
      body: SafeArea(
        child: Column(
          children: [
            const ShiftBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(color: C.amber, shape: BoxShape.circle),
                        ),
                        Gap.w8,
                        Text('CLIENTE EN ESTACIÓN',
                            style: mono(size: 11, color: C.amber, letterSpacing: 1.6)),
                        const Spacer(),
                        Text('hace ${t.minutesAgo} min', style: mono(size: 11, color: C.mutedDim)),
                      ],
                    ),
                    Gap.h16,
                    Text('Surtidor ${t.pump ?? '—'}',
                        style: display(size: 46, weight: FontWeight.w700, height: 1)),
                    Gap.h8,
                    Text('${t.code} · ${t.customer}', style: body(size: 15, color: C.muted)),
                    Gap.h24,
                    OCard(
                      color: C.surface,
                      child: Row(
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: C.surfaceHi,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: C.line),
                            ),
                            child: const Icon(Icons.person_outline, size: 30, color: C.mutedDim),
                          ),
                          Gap.w16,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                OLabel('Foto de verificación'),
                                Gap.h8,
                                Text(t.customer, style: body(size: 15, weight: FontWeight.w700)),
                                Gap.h4,
                                Text('${t.vehicle}\nTablilla ${t.plate}',
                                    style: body(size: 12, color: C.mutedDim)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Gap.h12,
                    OCard(
                      color: C.surface,
                      child: Column(
                        children: [
                          ORow('Combustible', t.grade.label, valueColor: t.grade.color),
                          ORow('Techo autorizado', '\$${t.cap.toStringAsFixed(2)}'),
                          ORow('Minimarket', '${t.items.length} artículo(s)'),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Container(height: 1, color: C.line),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                OLabel('edge_transaction_uuid'),
                                Gap.h4,
                                Text(t.edgeTxUuid, style: mono(size: 10, color: C.muted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (t.items.isNotEmpty) ...[
                      Gap.h12,
                      OCard(
                        color: C.surface,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OLabel('Pedido a preparar'),
                            Gap.h8,
                            ...t.items.map((i) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Text('${i.qty}×',
                                          style: mono(size: 12, color: C.green, weight: FontWeight.w700)),
                                      Gap.w8,
                                      Expanded(child: Text(i.name, style: body(size: 13))),
                                      Text(i.aisle, style: mono(size: 10, color: C.mutedDim)),
                                    ],
                                  ),
                                )),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Row(
                children: [
                  Expanded(
                    child: OButton(
                      label: 'Reasignar',
                      variant: OButtonVariant.ghost,
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                  Gap.w12,
                  Expanded(
                    flex: 2,
                    child: OButton(
                      label: t.items.isEmpty ? 'Aceptar y surtir' : 'Aceptar y preparar',
                      onTap: () async {
                        await s.accept(t);
                        if (!context.mounted) return;
                        if (s.error != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(s.error!)),
                          );
                          return;
                        }
                        Navigator.pushReplacementNamed(
                          context,
                          t.hasItems ? Routes.picking : Routes.delivery,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
