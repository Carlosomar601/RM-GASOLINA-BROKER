import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/alert_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/delivery_screen.dart';
import 'screens/integrations_screen.dart';
import 'screens/login_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/picking_screen.dart';
import 'screens/roles_screen.dart';
import 'state/shift_state.dart';
import 'theme/tokens.dart';
import 'theme/typography.dart';

class Routes {
  Routes._();
  static const dashboard = '/';
  static const login = '/turno';
  static const orders = '/ordenes';
  static const alert = '/alerta';
  static const picking = '/picking';
  static const delivery = '/entrega';
  static const roles = '/roles';
  static const integrations = '/integraciones';
}

class EmployeeApp extends StatefulWidget {
  const EmployeeApp({super.key});

  @override
  State<EmployeeApp> createState() => _EmployeeAppState();
}

class _EmployeeAppState extends State<EmployeeApp> {
  final ShiftState _state = ShiftState();
  bool _booting = true;
  bool _resume = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: C.ink,
    ));
    _boot();
  }

  /// Reinstala el turno guardado antes de decidir la primera pantalla.
  Future<void> _boot() async {
    final ok = await _state.restoreSession();
    if (!mounted) return;
    setState(() {
      _booting = false;
      _resume = ok || !_state.live;
    });
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return MaterialApp(
        title: 'Octano · Empleado',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Scaffold(backgroundColor: C.ink, body: SizedBox.shrink()),
      );
    }
    return ShiftScope(
      state: _state,
      child: MaterialApp(
        title: 'Octano · Empleado',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        initialRoute: _resume ? Routes.dashboard : Routes.login,
        routes: {
          Routes.dashboard: (_) => const DashboardScreen(),
          Routes.login: (_) => const LoginScreen(),
          Routes.orders: (_) => const OrdersScreen(),
          Routes.alert: (_) => const AlertScreen(),
          Routes.picking: (_) => const PickingScreen(),
          Routes.delivery: (_) => const DeliveryScreen(),
          Routes.roles: (_) => const RolesScreen(),
          Routes.integrations: (_) => const IntegrationsScreen(),
        },
      ),
    );
  }
}

/// Barra superior del handheld: estación, turno y estado de conexión.
class ShiftBar extends StatelessWidget {
  const ShiftBar({super.key, this.trailing});
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final s = ShiftScope.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
      decoration: const BoxDecoration(
        color: C.inkDeep,
        border: Border(bottom: BorderSide(color: C.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: C.green, borderRadius: BorderRadius.circular(9)),
            child: Text('O',
                style: display(size: 17, weight: FontWeight.w700, color: const Color(0xFF0C130F))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.employee.station,
                    style: display(size: 14, weight: FontWeight.w600, letterSpacing: -0.1)),
                Text('${s.employee.name} · ${s.employee.badge}',
                    style: mono(size: 10, color: C.mutedDim)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
          const SizedBox(width: 8),
          _dot(
            s.cloudOnline ? C.green : C.red,
            s.live ? (s.streamConnected ? 'LIVE' : (s.cloudOnline ? 'CLOUD' : 'OFF')) : 'DEMO',
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color, String label) => Row(
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: mono(size: 9, color: color)),
        ],
      );
}
