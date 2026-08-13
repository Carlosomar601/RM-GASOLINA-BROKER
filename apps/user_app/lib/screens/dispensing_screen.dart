import 'package:flutter/material.dart';

import '../app.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/ui.dart';

/// Paso 9 — surtido en vivo. El contador refleja el pulso del surtidor.
class DispensingScreen extends StatefulWidget {
  const DispensingScreen({super.key});

  @override
  State<DispensingScreen> createState() => _DispensingScreenState();
}

class _DispensingScreenState extends State<DispensingScreen> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.read(context).startDispensing();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final pct = s.fuelCap == 0 ? 0.0 : (s.dispensedAmount / s.fuelCap).clamp(0.0, 1.0).toDouble();
    final done = !s.dispensing && s.dispensedAmount > 0;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            OHeader(
              title: done ? 'Surtido completo' : 'Surtiendo',
              step: 'Paso 3 de 4 · surtidor ${s.pumpNumber ?? '—'}',
              subtitle: s.station?.name,
              action: OPill(done ? 'CERRADO' : 'EN VIVO', color: done ? C.muted : C.green, filled: !done),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: OStepper(current: 2),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: SizedBox(
                        width: 232,
                        height: 232,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 232,
                              height: 232,
                              child: CircularProgressIndicator(
                                value: pct,
                                strokeWidth: 12,
                                backgroundColor: C.line,
                                valueColor: AlwaysStoppedAnimation(s.fuelType.color),
                                strokeCap: StrokeCap.round,
                              ),
                            ),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                OLabel('Dispensado'),
                                Gap.h8,
                                OMoney(s.dispensedAmount, size: 40, color: C.bone),
                                Gap.h4,
                                Text('${s.dispensedLiters.toStringAsFixed(2)} L',
                                    style: mono(size: 15, color: C.muted)),
                                Gap.h8,
                                Text('de \$${s.fuelCap.toStringAsFixed(2)} autorizado',
                                    style: mono(size: 10, color: C.mutedDim)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Gap.h32,
                    OCard(
                      child: Column(
                        children: [
                          ORow('Combustible', s.fuelType.label, valueColor: s.fuelType.color),
                          ORow('Precio', '\$${s.pricePerLiter.toStringAsFixed(2)} / L'),
                          ORow('Minimarket · ${s.cartCount} art.',
                              '\$${s.itemsTotal.toStringAsFixed(2)}'),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Container(height: 1, color: C.line),
                          ),
                          ORow('Total a cobrar', '\$${s.finalTotal.toStringAsFixed(2)}',
                              strong: true, valueColor: C.green),
                          ORow('Se libera', '\$${s.releasedHold.toStringAsFixed(2)}',
                              valueColor: C.amber),
                        ],
                      ),
                    ),
                    Gap.h16,
                    if (s.cart.isNotEmpty)
                      OCard(
                        child: Row(
                          children: [
                            const Icon(Icons.shopping_bag_outlined, size: 20, color: C.green),
                            Gap.w12,
                            Expanded(
                              child: Text('Tu pedido del minimarket va camino al carro',
                                  style: body(size: 13, color: C.muted)),
                            ),
                            OPill('EN RUTA', color: C.green),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: done
                  ? OButton(
                      label: 'Ver recibo',
                      onTap: () async {
                        await s.settle();
                        if (!context.mounted) return;
                        Navigator.pushReplacementNamed(context, Routes.receipt);
                      },
                    )
                  : OButton(
                      label: 'Detener surtido',
                      variant: OButtonVariant.danger,
                      onTap: s.stopDispensing,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
