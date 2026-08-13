import 'package:flutter/material.dart';

import '../app.dart';
import '../models/models.dart';
import '../state/shift_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/ui.dart';

/// 2 · Órdenes: cola completa con filtros por estado.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  TaskStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final s = ShiftScope.of(context);
    final list = _filter == null ? s.tasks : s.tasks.where((t) => t.status == _filter).toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ShiftBar(),
            OHeader(
              title: 'Órdenes',
              step: '${s.pendingCount} abiertas · ${s.tasks.length} hoy',
              onBack: () => Navigator.pop(context),
            ),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                children: [
                  _chip('Todas', _filter == null, () => setState(() => _filter = null)),
                  ...TaskStatus.values.map((st) =>
                      _chip(st.label, _filter == st, () => setState(() => _filter = st))),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                itemCount: list.length,
                separatorBuilder: (_, __) => Gap.h10,
                itemBuilder: (_, i) => _card(context, s, list[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool sel, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? C.green : C.surface,
              borderRadius: Radii.pill,
              border: Border.all(color: sel ? C.green : C.line),
            ),
            child: Text(label,
                style: body(
                    size: 12,
                    weight: FontWeight.w600,
                    color: sel ? const Color(0xFF0C130F) : C.muted)),
          ),
        ),
      );

  Widget _card(BuildContext context, ShiftState s, Task t) => OCard(
        padding: const EdgeInsets.all(15),
        accent: t.status == TaskStatus.entrante ? C.amber : null,
        onTap: () {
          s.select(t);
          Navigator.pushNamed(
            context,
            switch (t.status) {
              TaskStatus.entrante => Routes.alert,
              TaskStatus.preparando || TaskStatus.aceptada => Routes.picking,
              _ => Routes.delivery,
            },
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(t.code, style: mono(size: 13, color: C.bone, weight: FontWeight.w700)),
                Gap.w8,
                OPill(t.status.label.toUpperCase(), color: t.status.color),
                const Spacer(),
                Text('hace ${t.minutesAgo} min', style: mono(size: 10, color: C.mutedDim)),
              ],
            ),
            Gap.h12,
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.customer, style: body(size: 14, weight: FontWeight.w600)),
                      Gap.h4,
                      Text('${t.vehicle} · ${t.plate}',
                          style: body(size: 12, color: C.mutedDim)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('#${t.pump ?? '—'}',
                        style: display(size: 20, color: t.grade.color, weight: FontWeight.w700)),
                    Text(t.grade.label, style: mono(size: 9, color: C.mutedDim)),
                  ],
                ),
              ],
            ),
            Gap.h12,
            Container(height: 1, color: C.line),
            Gap.h10,
            Row(
              children: [
                Text('Techo \$${t.cap.toStringAsFixed(0)}',
                    style: mono(size: 11, color: C.muted)),
                Gap.w12,
                Text('${t.pickedCount}/${t.items.length} art.',
                    style: mono(size: 11, color: t.allPicked ? C.green : C.amber)),
                const Spacer(),
                if (t.status == TaskStatus.cerrada)
                  Text('Cobrado \$${t.dispensed.toStringAsFixed(2)}',
                      style: mono(size: 11, color: C.green, weight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      );
}
