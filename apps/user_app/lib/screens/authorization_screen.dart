import 'package:flutter/material.dart';

import '../app.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/ui.dart';

/// Paso 7 — retención / autorización de la tarjeta.
class AuthorizationScreen extends StatefulWidget {
  const AuthorizationScreen({super.key});

  @override
  State<AuthorizationScreen> createState() => _AuthorizationScreenState();
}

class _AuthorizationScreenState extends State<AuthorizationScreen> {
  bool _working = false;

  Future<void> _authorize() async {
    setState(() => _working = true);
    final s = AppScope.of(context);
    if (!s.live) await Future<void>.delayed(const Duration(milliseconds: 1100));
    final ok = await s.authorize();
    if (!mounted) return;
    if (!ok) {
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.error ?? 'No se pudo autorizar la retención')),
      );
      return;
    }
    Navigator.pushReplacementNamed(context, Routes.arrival);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            OHeader(
              title: 'Autorización',
              step: 'Paso 1 de 4 · retención',
              onBack: _working ? null : () => Navigator.pop(context),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: OStepper(current: 0),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OCard(
                      color: C.inkDeep,
                      accent: C.amber,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              OLabel('Se retiene ahora'),
                              OPill('NO ES COBRO', color: C.amber),
                            ],
                          ),
                          Gap.h12,
                          OMoney(s.authorizedHold, size: 42, color: C.amber),
                          Gap.h8,
                          Text('Techo \$${s.fuelCap.toStringAsFixed(2)} + minimarket \$${s.itemsTotal.toStringAsFixed(2)}',
                              style: body(size: 12, color: C.mutedDim)),
                        ],
                      ),
                    ),
                    Gap.h16,
                    OCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OLabel('Resumen'),
                          Gap.h8,
                          ORow('Estación', s.station?.name ?? '—'),
                          ORow('Combustible', s.fuelType.label,
                              valueColor: s.fuelType.color),
                          ORow('Precio', '\$${s.pricePerLiter.toStringAsFixed(2)} / L'),
                          ORow('Vehículo', s.vehicle.plate),
                          if (s.cart.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Container(height: 1, color: C.line),
                            ),
                            ...s.cart.map((l) => ORow('${l.qty}× ${l.product.name}',
                                '\$${l.total.toStringAsFixed(2)}')),
                          ],
                        ],
                      ),
                    ),
                    Gap.h16,
                    OCard(
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: C.surfaceHi,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: C.line),
                            ),
                            child: Text('VISA', style: mono(size: 9, color: C.bone)),
                          ),
                          Gap.w12,
                          Expanded(
                            child: Text('Tarjeta •••• ${s.cardLast4}',
                                style: body(size: 14, weight: FontWeight.w600)),
                          ),
                          Text('Cambiar', style: body(size: 13, color: C.green, weight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Gap.h16,
                    Text(
                      'Al autorizar, tu banco reserva el monto. Cobramos únicamente el combustible dispensado más los artículos entregados; el resto se libera en 24–72 h.',
                      style: body(size: 12, color: C.mutedDim),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: _working
                  ? OCard(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      color: C.surface,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: C.green),
                          ),
                          Gap.w12,
                          Text('Autorizando con el banco…',
                              style: body(size: 14, color: C.muted, weight: FontWeight.w600)),
                        ],
                      ),
                    )
                  : OButton(
                      label: 'Autorizar \$${s.authorizedHold.toStringAsFixed(2)}',
                      onTap: _authorize,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
