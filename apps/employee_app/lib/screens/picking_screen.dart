import 'package:flutter/material.dart';

import '../app.dart';
import '../models/models.dart';
import '../state/shift_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/ui.dart';

/// 4 · Picking del minimarket con sustituciones.
class PickingScreen extends StatelessWidget {
  const PickingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = ShiftScope.of(context);
    final t = s.active ?? s.tasks.first;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ShiftBar(),
            OHeader(
              title: 'Preparar pedido',
              step: '${t.code} · surtidor ${t.pump ?? '—'}',
              subtitle: '${t.customer} · ${t.plate}',
              onBack: () => Navigator.pop(context),
              action: OPill('${t.pickedCount}/${t.items.length}',
                  color: t.allPicked ? C.green : C.amber, filled: t.allPicked),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                children: [
                  ...t.items.map((i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _item(s, i),
                      )),
                  if (t.items.isEmpty)
                    OCard(
                      child: Text('Esta orden es solo combustible.',
                          style: body(size: 13, color: C.muted)),
                    ),
                  Gap.h16,
                  OCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OLabel('Combustible en esta orden'),
                        Gap.h8,
                        ORow('Grado', t.grade.label, valueColor: t.grade.color),
                        ORow('Techo', '\$${t.cap.toStringAsFixed(2)}'),
                        ORow('Surtidor', '#${t.pump ?? '—'}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: OButton(
                label: t.allPicked ? 'Llevar al carro' : 'Falta ${t.items.length - t.pickedCount} artículo(s)',
                onTap: t.allPicked
                    ? () {
                        s.readyForDelivery(t);
                        Navigator.pushReplacementNamed(context, Routes.delivery);
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(ShiftState s, PickItem i) => OCard(
        padding: const EdgeInsets.all(14),
        accent: i.picked ? C.green : null,
        onTap: () => s.togglePick(i),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: i.picked ? C.green : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: i.picked ? C.green : C.line, width: 1.5),
              ),
              child: i.picked
                  ? const Icon(Icons.check, size: 18, color: Color(0xFF0C130F))
                  : null,
            ),
            Gap.w12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${i.qty}×',
                          style: mono(size: 14, color: C.green, weight: FontWeight.w700)),
                      Gap.w8,
                      Expanded(
                        child: Text(
                          i.name,
                          style: body(
                            size: 14,
                            weight: FontWeight.w600,
                            color: i.picked ? C.muted : C.bone,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Gap.h4,
                  Row(
                    children: [
                      Text('Ubicación ${i.aisle}', style: mono(size: 10, color: C.mutedDim)),
                      if (i.substituted) ...[Gap.w8, OPill('SUSTITUIDO', color: C.amber)],
                    ],
                  ),
                ],
              ),
            ),
            if (!i.picked)
              TextButton(
                onPressed: () => s.substitute(i),
                child: Text('Sustituir',
                    style: body(size: 12, color: C.amber, weight: FontWeight.w600)),
              ),
          ],
        ),
      );
}
