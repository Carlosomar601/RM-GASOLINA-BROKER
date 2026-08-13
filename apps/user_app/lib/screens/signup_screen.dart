import 'package:flutter/material.dart';

import '../app.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/ui.dart';

/// Paso 2 — crear cuenta y abrir la cartera (wallet) con una tarjeta.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  int _step = 0;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _plate = TextEditingController();
  final _card = TextEditingController();
  double _autoTopUp = 25;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _plate.dispose();
    _card.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final s = AppScope.of(context);
    final ok = await s.register(
      fullName: _name.text.trim().isEmpty ? 'Cliente Octano' : _name.text.trim(),
      phone: _phone.text.trim(),
      // El alta del mockup no pide contraseña: el broker recibe un PIN
      // derivado (últimos 4 del teléfono) hasta que definamos OTP por SMS.
      password: _pinFromPhone(_phone.text),
      plate: _plate.text.trim(),
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.error ?? 'No se pudo crear la cuenta')),
      );
      return;
    }
    await s.topUpWallet(_autoTopUp);
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, Routes.stations, (r) => false);
  }

  static String _pinFromPhone(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    return d.length >= 4 ? d.substring(d.length - 4) : '0000';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            OHeader(
              title: _step == 0 ? 'Crear cuenta' : 'Abrir cartera',
              step: 'Paso ${_step + 1} de 2',
              subtitle: _step == 0
                  ? 'Tus datos y tu vehículo para la entrega al carro.'
                  : 'La tarjeta se usa para la retención; el cobro final es lo dispensado.',
              onBack: () => _step == 0 ? Navigator.pop(context) : setState(() => _step = 0),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: OStepper(current: _step, total: 2),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                child: _step == 0 ? _identity() : _wallet(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: OButton(
                label: _step == 0 ? 'Continuar' : 'Abrir cartera y entrar',
                onTap: () => _step == 0 ? setState(() => _step = 1) : _finish(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _identity() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OField(label: 'Nombre completo', hint: 'Carlos Omar Rivera', controller: _name),
          Gap.h16,
          OField(label: 'Teléfono', hint: '787 000 0000', controller: _phone, keyboard: TextInputType.phone),
          Gap.h16,
          OField(label: 'Tablilla del vehículo', hint: 'HJK-482', controller: _plate),
          Gap.h24,
          OCard(
            child: Row(
              children: [
                const Icon(Icons.photo_camera_outlined, size: 20, color: C.green),
                Gap.w12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Foto de verificación',
                          style: body(size: 14, weight: FontWeight.w600)),
                      Gap.h4,
                      Text('El empleado la usa para confirmar a quién entrega en el carro.',
                          style: body(size: 12, color: C.mutedDim)),
                    ],
                  ),
                ),
                Gap.w8,
                OPill('Tomar', color: C.green),
              ],
            ),
          ),
        ],
      );

  Widget _wallet() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OCard(
            color: C.inkDeep,
            accent: C.green,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OLabel('Cartera Octano'),
                    OPill('PREPAGO', color: C.green),
                  ],
                ),
                Gap.h16,
                const OMoney(0, size: 38),
                Gap.h4,
                Text('Balance inicial · se recarga al abrir',
                    style: body(size: 12, color: C.mutedDim)),
              ],
            ),
          ),
          Gap.h24,
          OField(label: 'Tarjeta', hint: '4242 4242 4242 4417', controller: _card, keyboard: TextInputType.number),
          Gap.h24,
          OLabel('Recarga inicial'),
          Gap.h12,
          Row(
            children: [10, 25, 50, 75].map((v) {
              final sel = _autoTopUp == v;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _autoTopUp = v.toDouble()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sel ? C.green.withOpacity(0.14) : C.surface,
                        borderRadius: Radii.field,
                        border: Border.all(color: sel ? C.green : C.line),
                      ),
                      child: Text('\$$v',
                          style: mono(size: 14, color: sel ? C.green : C.bone, weight: FontWeight.w600)),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          Gap.h24,
          OCard(
            color: C.surface,
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, size: 20, color: C.muted),
                Gap.w12,
                Expanded(
                  child: Text(
                    'Nunca cobramos el techo completo. Autorizamos una retención y liberamos la diferencia al cerrar el surtido.',
                    style: body(size: 12, color: C.muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}
