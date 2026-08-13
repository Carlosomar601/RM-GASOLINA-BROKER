import 'package:flutter/material.dart';

import '../app.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/ui.dart';

/// Paso 3 — estaciones cercanas, balance de cartera y acceso rápido a voz.
class StationsScreen extends StatelessWidget {
  const StationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Wordmark(size: 20),
                  GestureDetector(
                    onTap: () => Navigator.pushNamed(context, Routes.profile),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: Radii.pill,
                        border: Border.all(color: C.line),
                        color: C.surface,
                      ),
                      child: Text(
                        s.customerName.substring(0, 1),
                        style: display(size: 16, color: C.green),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                children: [
                  _walletCard(context, s),
                  Gap.h16,
                  OCard(
                    onTap: () => Navigator.pushNamed(context, Routes.voice),
                    color: C.surface,
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: C.amber.withOpacity(0.14),
                            borderRadius: Radii.pill,
                          ),
                          child: const Icon(Icons.mic_none, color: C.amber, size: 22),
                        ),
                        Gap.w12,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Compra por voz', style: body(size: 15, weight: FontWeight.w600)),
                              Gap.h4,
                              Text('«Ponme \$20 de regular y un café»',
                                  style: body(size: 12, color: C.mutedDim)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: C.mutedDim),
                      ],
                    ),
                  ),
                  Gap.h24,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OLabel('Estaciones cercanas'),
                      Text('Ordenar por distancia', style: mono(size: 10, color: C.green)),
                    ],
                  ),
                  Gap.h12,
                  ...s.stations.map((st) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _stationCard(context, s, st),
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _walletCard(BuildContext context, AppState s) => OCard(
        color: C.inkDeep,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OLabel('Cartera · balance'),
                OPill('•••• ${s.cardLast4}', color: C.muted),
              ],
            ),
            Gap.h12,
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                OMoney(s.walletBalance, size: 34, color: C.bone),
                Gap.w12,
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('disponible', style: body(size: 12, color: C.mutedDim)),
                ),
              ],
            ),
            Gap.h16,
            Row(
              children: [
                Expanded(
                  child: OButton(
                    label: 'Recargar',
                    icon: Icons.add,
                    onTap: () {
                      s.topUpWallet(25);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: C.surfaceHi,
                          content: Text('Recarga de \$25.00 aplicada',
                              style: body(size: 13, color: C.bone)),
                        ),
                      );
                    },
                  ),
                ),
                Gap.w12,
                Expanded(
                  child: OButton(
                    label: 'Movimientos',
                    variant: OButtonVariant.ghost,
                    onTap: () => Navigator.pushNamed(context, Routes.profile),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _stationCard(BuildContext context, AppState s, Station st) => OCard(
        onTap: st.open
            ? () {
                s.selectStation(st);
                Navigator.pushNamed(context, Routes.catalog);
              }
            : null,
        color: st.open ? C.surface : C.surface.withOpacity(0.55),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(st.name, style: display(size: 17, weight: FontWeight.w600)),
                      Gap.h4,
                      Text('${st.address} · ${st.town}',
                          style: body(size: 12, color: C.mutedDim)),
                    ],
                  ),
                ),
                Gap.w8,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${st.distanceKm.toStringAsFixed(1)} km',
                        style: mono(size: 13, color: C.bone, weight: FontWeight.w600)),
                    Gap.h4,
                    st.open
                        ? OPill('ABIERTA · ${st.waitMinutes} min', color: C.green)
                        : OPill('CERRADA', color: C.red),
                  ],
                ),
              ],
            ),
            Gap.h16,
            Container(height: 1, color: C.line),
            Gap.h12,
            Row(
              children: st.availableFuels.map((t) {
                return Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.short, style: mono(size: 10, color: C.mutedDim, letterSpacing: 1)),
                      Gap.h4,
                      Text('\$${st.priceOf(t).toStringAsFixed(2)}',
                          style: mono(size: 15, color: t.color, weight: FontWeight.w600)),
                      Text('por litro', style: mono(size: 9, color: C.mutedDim)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );
}
