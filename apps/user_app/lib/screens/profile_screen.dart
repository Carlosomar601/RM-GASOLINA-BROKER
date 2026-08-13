import 'package:flutter/material.dart';

import '../app.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/ui.dart';

/// Paso 11 — perfil: identidad verificada por foto, vehículo, pagos.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            OHeader(
              title: 'Perfil',
              step: 'Cuenta',
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                children: [
                  OCard(
                    color: C.inkDeep,
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Container(
                          width: 62,
                          height: 62,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: C.green.withOpacity(0.14),
                            borderRadius: Radii.pill,
                            border: Border.all(color: C.green.withOpacity(0.45)),
                          ),
                          child: Text(s.customerName.substring(0, 1),
                              style: display(size: 26, color: C.green)),
                        ),
                        Gap.w16,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.customerName, style: display(size: 19)),
                              Gap.h4,
                              Text(s.phone, style: mono(size: 12, color: C.mutedDim)),
                              Gap.h8,
                              s.photoVerified
                                  ? OPill('FOTO VERIFICADA', color: C.green)
                                  : OPill('FALTA FOTO', color: C.amber),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Gap.h16,
                  OCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OLabel('Identidad para entrega al carro'),
                        Gap.h12,
                        Row(
                          children: [
                            Container(
                              width: 84,
                              height: 84,
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
                                  Text(
                                    'El empleado ve esta foto al llegar al surtidor para confirmar a quién entrega.',
                                    style: body(size: 12, color: C.muted),
                                  ),
                                  Gap.h12,
                                  OButton(
                                    label: 'Actualizar foto',
                                    variant: OButtonVariant.ghost,
                                    expand: false,
                                    icon: Icons.photo_camera_outlined,
                                    onTap: () {},
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Gap.h16,
                  OCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OLabel('Vehículo'),
                        Gap.h8,
                        ORow('Tablilla', s.vehicle.plate),
                        ORow('Modelo', s.vehicle.make),
                        ORow('Color', s.vehicle.color),
                        ORow('Tanque', '${s.vehicle.tankLiters.toStringAsFixed(0)} L'),
                      ],
                    ),
                  ),
                  Gap.h16,
                  OCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OLabel('Pagos'),
                        Gap.h8,
                        ORow('Cartera', '\$${s.walletBalance.toStringAsFixed(2)}'),
                        ORow('Tarjeta', 'VISA •••• ${s.cardLast4}'),
                        ORow('Recarga automática', 'Al bajar de \$10'),
                      ],
                    ),
                  ),
                  Gap.h16,
                  OCard(
                    child: Column(
                      children: [
                        _link('Historial de órdenes', Icons.receipt_long_outlined),
                        _link('Notificaciones', Icons.notifications_none),
                        _link('Idioma · Español', Icons.translate),
                        _link('Ayuda y soporte', Icons.help_outline),
                      ],
                    ),
                  ),
                  Gap.h24,
                  OButton(
                    label: 'Cerrar sesión',
                    variant: OButtonVariant.danger,
                    onTap: () {
                      s.signOut();
                      Navigator.pushNamedAndRemoveUntil(context, Routes.login, (r) => false);
                    },
                  ),
                  Gap.h16,
                  Center(child: OLabel('Octano · Retail Manager PR · v0.1')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _link(String label, IconData icon) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 19, color: C.muted),
            Gap.w12,
            Expanded(child: Text(label, style: body(size: 14))),
            const Icon(Icons.chevron_right, size: 18, color: C.mutedDim),
          ],
        ),
      );
}
