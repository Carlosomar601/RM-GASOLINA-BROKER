import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/arrival_screen.dart';
import 'screens/authorization_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/dispensing_screen.dart';
import 'screens/fuel_screen.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/receipt_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/stations_screen.dart';
import 'screens/voice_screen.dart';
import 'state/app_state.dart';
import 'theme/tokens.dart';
import 'theme/typography.dart';

class Routes {
  Routes._();
  static const login = '/';
  static const signup = '/crear-cuenta';
  static const stations = '/estaciones';
  static const catalog = '/catalogo';
  static const voice = '/voz';
  static const fuel = '/combustible';
  static const authorization = '/autorizacion';
  static const arrival = '/llegada';
  static const dispensing = '/surtiendo';
  static const receipt = '/recibo';
  static const profile = '/perfil';
}

class OctanoApp extends StatefulWidget {
  const OctanoApp({super.key});

  @override
  State<OctanoApp> createState() => _OctanoAppState();
}

class _OctanoAppState extends State<OctanoApp> {
  final AppState _state = AppState();
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

  /// Reinstala la sesión guardada antes de decidir la primera pantalla.
  Future<void> _boot() async {
    final ok = await _state.restoreSession();
    if (!mounted) return;
    setState(() {
      _booting = false;
      _resume = ok;
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
        title: 'Octano',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const _Splash(),
      );
    }
    return AppScope(
      state: _state,
      child: MaterialApp(
        title: 'Octano',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        initialRoute: _resume ? Routes.stations : Routes.login,
        routes: {
          Routes.login: (_) => const LoginScreen(),
          Routes.signup: (_) => const SignupScreen(),
          Routes.stations: (_) => const StationsScreen(),
          Routes.catalog: (_) => const CatalogScreen(),
          Routes.voice: (_) => const VoiceScreen(),
          Routes.fuel: (_) => const FuelScreen(),
          Routes.authorization: (_) => const AuthorizationScreen(),
          Routes.arrival: (_) => const ArrivalScreen(),
          Routes.dispensing: (_) => const DispensingScreen(),
          Routes.receipt: (_) => const ReceiptScreen(),
          Routes.profile: (_) => const ProfileScreen(),
        },
      ),
    );
  }
}

/// Pantalla de arranque mientras se reinstala la sesión guardada.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: C.ink,
        body: Center(child: Wordmark(size: 26)),
      );
}

/// Marca reutilizable (wordmark Octano).
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 22, this.showBadge = true});
  final double size;
  final bool showBadge;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size * 1.35,
            height: size * 1.35,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: C.green,
              borderRadius: BorderRadius.circular(size * 0.38),
            ),
            child: Text(
              'O',
              style: display(
                size: size * 0.82,
                weight: FontWeight.w700,
                color: const Color(0xFF0C130F),
              ),
            ),
          ),
          SizedBox(width: size * 0.45),
          Text('Octano', style: display(size: size, weight: FontWeight.w700)),
          if (showBadge) ...[
            SizedBox(width: size * 0.35),
            Text('PR', style: mono(size: size * 0.45, color: C.mutedDim)),
          ],
        ],
      );
}
