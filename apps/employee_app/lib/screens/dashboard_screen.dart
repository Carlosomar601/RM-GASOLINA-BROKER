import 'package:flutter/material.dart';

import '../app.dart';
import '../models/models.dart';
import '../state/shift_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/ui.dart';

/// 1 · Dashboard del turno.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = ShiftScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ShiftBar(
              trailing: IconButton(
                onPressed: () => Navigator.pushNamed(context, Routes.roles),
                icon: const Icon(Icons.settings_outlined, size: 20, color: C.muted),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OLabel('Turno'),
                          Gap.h4,
                          Text(s.shiftOpen ? 'Abierto · 6:00 a 14:00' : 'Cerrado',
                              style: display(size: 20)),
                        ],
                      ),
                      Switch(
                        value: s.shiftOpen,
                        activeColor: C.green,
                        onChanged: (_) => s.toggleShift(),
                      ),
                    ],
                  ),
                  Gap.h16,
                  Row(
                    children: [
                      Expanded(child: _stat('Atendidos hoy', '${s.servedToday}', C.bone)),
                      Gap.w12,
                      Expanded(child: _stat('Litros', s.volumeToday.toStringAsFixed(0), C.green)),
                      Gap.w12,
                      Expanded(child: _stat('Prom. min', s.avgMinutes.toStringAsFixed(1), C.amber)),
                    ],
                  ),
                  Gap.h16,
                  if (s.incoming.isNotEmpty)
                    OCard(
                      accent: C.amber,
                      color: C.inkDeep,
                      onTap: () => Navigator.pushNamed(context, Routes.alert),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: C.amber.withOpacity(0.16),
                              borderRadius: Radii.pill,
                            ),
                            child: const Icon(Icons.notifications_active_outlined,
                                color: C.amber, size: 22),
                          ),
                          Gap.w12,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${s.incoming.length} orden(es) entrante(s)',
                                    style: body(size: 15, weight: FontWeight.w700)),
                                Gap.h4,
                                Text('Cliente en camino · toca para ver',
                                    style: body(size: 12, color: C.mutedDim)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: C.amber),
                        ],
                      ),
                    ),
                  Gap.h24,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OLabel('Cola del turno · ${s.pendingCount} abiertas'),
                      GestureDetector(
                        onTap: () => Navigator.pushNamed(context, Routes.orders),
                        child: Text('Ver todas', style: mono(size: 10, color: C.green)),
                      ),
                    ],
                  ),
                  Gap.h12,
                  ...s.openTasks.map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _taskRow(context, s, t),
                      )),
                  Gap.h16,
                  OCard(
                    onTap: () => Navigator.pushNamed(context, Routes.integrations),
                    child: Row(
                      children: [
                        Icon(s.pumpsOnline ? Icons.local_gas_station : Icons.error_outline,
                            size: 20, color: s.pumpsOnline ? C.green : C.red),
                        Gap.w12,
                        Expanded(
                          child: Text(
                            s.pumpsOnline
                                ? 'Surtidores en línea · POS Retail Manager conectado'
                                : 'Surtidores sin conexión · revisar controlador',
                            style: body(size: 12, color: C.muted),
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 18, color: C.mutedDim),
                      ],
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

  Widget _stat(String label, String value, Color color) => OCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: mono(size: 22, color: color, weight: FontWeight.w600)),
            Gap.h4,
            Text(label, style: mono(size: 9, color: C.mutedDim)),
          ],
        ),
      );

  Widget _taskRow(BuildContext context, ShiftState s, Task t) => OCard(
        padding: const EdgeInsets.all(14),
        onTap: () {
          s.select(t);
          Navigator.pushNamed(
            context,
            t.status == TaskStatus.entrante
                ? Routes.alert
                : t.status == TaskStatus.preparando
                    ? Routes.picking
                    : Routes.delivery,
          );
        },
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.grade.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.grade.color.withOpacity(0.3)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('#${t.pump ?? '—'}',
                      style: mono(size: 14, color: t.grade.color, weight: FontWeight.w700)),
                  Text(t.grade.short, style: mono(size: 8, color: C.mutedDim)),
                ],
              ),
            ),
            Gap.w12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(t.code, style: mono(size: 12, color: C.bone, weight: FontWeight.w600)),
                      if (t.priority) ...[Gap.w8, OPill('PRIORIDAD', color: C.amber)],
                    ],
                  ),
                  Gap.h4,
                  Text('${t.customer} · ${t.plate}', style: body(size: 13)),
                  Gap.h4,
                  Text(
                    '\$${t.cap.toStringAsFixed(0)} techo · ${t.items.length} art. · hace ${t.minutesAgo} min',
                    style: mono(size: 10, color: C.mutedDim),
                  ),
                ],
              ),
            ),
            Gap.w8,
            OPill(t.status.label.toUpperCase(), color: t.status.color),
          ],
        ),
      );
}
