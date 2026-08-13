import 'package:flutter/material.dart';

import '../app.dart';
import '../state/shift_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/ui.dart';

/// 7 · Conexiones: POS Retail Manager, controlador de surtidores y nube.
class IntegrationsScreen extends StatelessWidget {
  const IntegrationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = ShiftScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ShiftBar(),
            OHeader(
              title: 'Conexiones',
              step: 'Diagnóstico local',
              subtitle: 'Estado de los enlaces de esta estación.',
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                children: [
                  _link(
                    'POS Retail Manager',
                    'Catálogo, precios e inventario del minimarket',
                    'pos-local:9443',
                    true,
                    null,
                  ),
                  Gap.h10,
                  _link(
                    'Controlador de surtidores',
                    'Autorización de bomba y pulsos de volumen',
                    'edge-controller:7002',
                    s.pumpsOnline,
                    s.togglePumps,
                  ),
                  Gap.h10,
                  _link(
                    'Nube Octano',
                    'Órdenes, retenciones y conciliación',
                    'api.octano.pr/v1',
                    s.cloudOnline,
                    s.toggleCloud,
                  ),
                  Gap.h10,
                  _link(
                    'Procesador de pagos',
                    'Retención, captura y liberación',
                    'tokenizado · PCI',
                    true,
                    null,
                  ),
                  Gap.h16,
                  OCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OLabel('Cola local'),
                        Gap.h8,
                        ORow('Eventos pendientes de sincronizar', s.cloudOnline ? '0' : '12',
                            valueColor: s.cloudOnline ? C.green : C.amber),
                        ORow('Última sincronización', s.cloudOnline ? 'hace 4 s' : 'hace 9 min'),
                        ORow('Modo sin conexión', s.cloudOnline ? 'Inactivo' : 'Activo',
                            valueColor: s.cloudOnline ? C.mutedDim : C.amber),
                        Gap.h12,
                        Text(
                          'Sin nube el handheld sigue surtiendo y guarda los eventos con su '
                          'edge_transaction_uuid; al reconectar se reenvían en orden.',
                          style: body(size: 12, color: C.mutedDim),
                        ),
                      ],
                    ),
                  ),
                  Gap.h12,
                  OCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OLabel('Dispositivo'),
                        Gap.h8,
                        ORow('Handheld', 'RM-HH-07'),
                        ORow('App', 'employee_app 0.1.0'),
                        ORow('Estación', s.employee.station),
                        ORow('Batería', '78%'),
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

  Widget _link(String title, String detail, String endpoint, bool up, VoidCallback? onToggle) =>
      OCard(
        accent: up ? null : C.red,
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: up ? C.green : C.red, shape: BoxShape.circle),
            ),
            Gap.w12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: body(size: 14, weight: FontWeight.w600)),
                  Gap.h4,
                  Text(detail, style: body(size: 11, color: C.mutedDim)),
                  Gap.h4,
                  Text(endpoint, style: mono(size: 10, color: C.muted)),
                ],
              ),
            ),
            if (onToggle != null)
              Switch(value: up, activeColor: C.green, onChanged: (_) => onToggle())
            else
              OPill(up ? 'EN LÍNEA' : 'CAÍDO', color: up ? C.green : C.red),
          ],
        ),
      );
}
