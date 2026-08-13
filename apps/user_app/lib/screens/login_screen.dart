import 'package:flutter/material.dart';

import '../app.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController(text: '787 555 0142');
  final _pass = TextEditingController(text: '••••••••');
  bool _hide = true;

  @override
  void dispose() {
    _phone.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _enter() async {
    final s = AppScope.of(context);
    final ok = await s.signIn(phone: _phone.text.trim(), password: _pass.text);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.error ?? 'No se pudo iniciar sesión')),
      );
      return;
    }
    Navigator.pushReplacementNamed(context, Routes.stations);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Wordmark(size: 24),
              Gap.h32,
              Text('Combustible prepago\nsin salir del carro.',
                  style: display(size: 30, height: 1.12)),
              Gap.h12,
              Text(
                'Autoriza un techo, llega a la estación y nosotros surtimos. Solo se cobra lo que se dispensa.',
                style: body(size: 14, color: C.mutedDim),
              ),
              Gap.h32,
              OField(label: 'Teléfono', hint: '787 000 0000', controller: _phone, keyboard: TextInputType.phone),
              Gap.h16,
              OField(
                label: 'Contraseña',
                controller: _pass,
                obscure: _hide,
                suffix: IconButton(
                  onPressed: () => setState(() => _hide = !_hide),
                  icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 19, color: C.mutedDim),
                ),
              ),
              Gap.h12,
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  child: Text('¿Olvidaste tu contraseña?',
                      style: body(size: 13, color: C.green, weight: FontWeight.w600)),
                ),
              ),
              Gap.h8,
              OButton(label: 'Entrar', onTap: _enter),
              Gap.h12,
              OButton(
                label: 'Continuar con Face ID',
                variant: OButtonVariant.ghost,
                icon: Icons.fingerprint,
                onTap: _enter,
              ),
              Gap.h32,
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('¿Primera vez? ', style: body(size: 14, color: C.mutedDim)),
                    GestureDetector(
                      onTap: () => Navigator.pushNamed(context, Routes.signup),
                      child: Text('Crear cuenta',
                          style: body(size: 14, color: C.green, weight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              Gap.h24,
              Center(child: OLabel('Retail Manager · Puerto Rico · v0.1')),
            ],
          ),
        ),
      ),
    );
  }
}
