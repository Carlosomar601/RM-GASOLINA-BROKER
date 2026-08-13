import 'package:flutter/material.dart';

import '../app.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/ui.dart';

/// Paso 6 — tipo de combustible y techo autorizado.
class FuelScreen extends StatelessWidget {
  const FuelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final st = s.station;
    final liters = s.pricePerLiter == 0 ? 0.0 : s.fuelCap / s.pricePerLiter;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            OHeader(
              title: 'Combustible',
              step: st?.name ?? 'Estación',
              subtitle: 'Elige el techo. Solo se cobra lo que entre al tanque.',
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OLabel('Tipo'),
                    Gap.h12,
                    Row(
                      children: s.availableFuels.map((t) {
                        final sel = s.fuelType == t;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => s.setFuelType(t),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                                decoration: BoxDecoration(
                                  color: sel ? t.color.withOpacity(0.14) : C.surface,
                                  borderRadius: Radii.field,
                                  border: Border.all(color: sel ? t.color : C.line),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t.short,
                                        style: display(
                                            size: 18,
                                            color: sel ? t.color : C.bone,
                                            weight: FontWeight.w700)),
                                    Gap.h4,
                                    Text('\$${(st?.priceOf(t) ?? 0).toStringAsFixed(2)}/L',
                                        style: mono(size: 11, color: C.mutedDim)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    Gap.h24,
                    OCard(
                      color: C.inkDeep,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OLabel('Techo autorizado'),
                          Gap.h12,
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              OMoney(s.fuelCap, size: 44, color: s.fuelType.color),
                              Gap.w12,
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text('≈ ${liters.toStringAsFixed(1)} L',
                                    style: mono(size: 14, color: C.muted)),
                              ),
                            ],
                          ),
                          Gap.h16,
                          Slider(
                            value: s.fuelCap.clamp(5.0, 120.0).toDouble(),
                            min: 5,
                            max: 120,
                            divisions: 23,
                            onChanged: (v) => s.setFuelCap(v.roundToDouble()),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('\$5', style: mono(size: 10, color: C.mutedDim)),
                              Text('\$120', style: mono(size: 10, color: C.mutedDim)),
                            ],
                          ),
                          Gap.h16,
                          Row(
                            children: [
                              ...[10, 20, 40].map((v) => Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: _quick('\$$v', s.fuelCap == v,
                                          () => s.setFuelCap(v.toDouble())),
                                    ),
                                  )),
                              Expanded(
                                child: _quick('Llenar', false, s.fillTank),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Gap.h24,
                    OCard(
                      child: Column(
                        children: [
                          ORow('Combustible (techo)', '\$${s.fuelCap.toStringAsFixed(2)}'),
                          ORow('Minimarket · ${s.cartCount} art.',
                              '\$${s.itemsTotal.toStringAsFixed(2)}'),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Container(height: 1, color: C.line),
                          ),
                          ORow('Retención a autorizar', '\$${s.authorizedHold.toStringAsFixed(2)}',
                              strong: true, valueColor: C.green),
                        ],
                      ),
                    ),
                    Gap.h16,
                    Text(
                      'La retención no es un cobro. Al cerrar el surtido cobramos lo dispensado y liberamos la diferencia.',
                      style: body(size: 12, color: C.mutedDim),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: OButton(
                label: 'Revisar autorización',
                onTap: () => Navigator.pushNamed(context, Routes.authorization),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quick(String label, bool sel, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? C.green.withOpacity(0.14) : C.surface,
            borderRadius: Radii.field,
            border: Border.all(color: sel ? C.green : C.line),
          ),
          child: Text(label,
              style: mono(size: 12, color: sel ? C.green : C.bone, weight: FontWeight.w600)),
        ),
      );
}
