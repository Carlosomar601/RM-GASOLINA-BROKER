import 'package:flutter/material.dart';

import '../app.dart';
import '../state/shift_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/ui.dart';

/// 6 · Roles y permisos del personal de la estación.
class RolesScreen extends StatelessWidget {
  const RolesScreen({super.key});

  static const _roles = <String, List<String>>{
    'Atendiente de pista': ['Ver órdenes', 'Surtir', 'Entregar', 'Sustituir artículos'],
    'Cajero': ['Ver órdenes', 'Cobrar en tienda', 'Cerrar surtido'],
    'Supervisor': ['Todo lo anterior', 'Reasignar órdenes', 'Anular retenciones', 'Ver conciliación'],
    'Gerente de estación': ['Todo', 'Precios', 'Inventario', 'Usuarios y turnos'],
  };

  @override
  Widget build(BuildContext context) {
    final s = ShiftScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ShiftBar(),
            OHeader(
              title: 'Roles y permisos',
              step: s.employee.badge,
              subtitle: 'Rol activo: ${s.employee.role}',
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                children: [
                  ..._roles.entries.map((e) {
                    final active = s.employee.role == e.key;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: OCard(
                        accent: active ? C.green : null,
                        onTap: () => s.setRole(e.key),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(e.key,
                                      style: display(size: 16, weight: FontWeight.w600)),
                                ),
                                if (active) OPill('ACTIVO', color: C.green, filled: true),
                              ],
                            ),
                            Gap.h10,
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: e.value
                                  .map((p) => Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: C.surfaceHi,
                                          borderRadius: Radii.pill,
                                          border: Border.all(color: C.line),
                                        ),
                                        child: Text(p, style: mono(size: 10, color: C.muted)),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  Gap.h16,
                  OCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OLabel('Turno'),
                        Gap.h8,
                        ORow('Estado', s.shiftOpen ? 'Abierto' : 'Cerrado',
                            valueColor: s.shiftOpen ? C.green : C.mutedDim),
                        ORow('Atendidos', '${s.servedToday}'),
                        ORow('Litros surtidos', s.volumeToday.toStringAsFixed(1)),
                        Gap.h12,
                        OButton(
                          label: s.shiftOpen ? 'Cerrar turno' : 'Abrir turno',
                          variant: s.shiftOpen ? OButtonVariant.danger : OButtonVariant.primary,
                          onTap: s.toggleShift,
                        ),
                      ],
                    ),
                  ),
                  Gap.h12,
                  OCard(
                    onTap: () => Navigator.pushNamed(context, Routes.integrations),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_outlined, size: 20, color: C.muted),
                        Gap.w12,
                        Expanded(
                          child: Text('Conexiones · POS, surtidores y nube',
                              style: body(size: 13, weight: FontWeight.w600)),
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
}
