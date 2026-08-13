import 'package:flutter/material.dart';

import '../app.dart';
import '../state/shift_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/ui.dart';

/// Entrada al turno: placa del empleado + PIN. Es la primera pantalla cuando
/// el handheld apunta a un broker real; en demo se salta.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _badge = TextEditingController();
  String _pin = '';
  bool _working = false;

  @override
  void dispose() {
    _badge.dispose();
    super.dispose();
  }

  Future<void> _enter() async {
    if (_badge.text.trim().isEmpty || _pin.length < 4) return;
    setState(() => _working = true);
    final s = ShiftScope.of(context);
    final ok = await s.signIn(badge: _badge.text.trim(), pin: _pin);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _working = false;
        _pin = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.error ?? 'Placa o PIN incorrectos')),
      );
      return;
    }
    Navigator.pushNamedAndRemoveUntil(context, Routes.dashboard, (r) => false);
  }

  void _tap(String d) {
    if (_working || _pin.length >= 6) return;
    setState(() => _pin += d);
    if (_pin.length == 6) _enter();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: C.green, borderRadius: BorderRadius.circular(10)),
                    child: Text('O',
                        style: display(size: 19, weight: FontWeight.w700, color: const Color(0xFF0C130F))),
                  ),
                  const SizedBox(width: 10),
                  Text('Octano · Pista', style: display(size: 19, weight: FontWeight.w700)),
                ],
              ),
              Gap.h24,
              Text('Abrir turno', style: display(size: 26)),
              Gap.h8,
              Text('Entra con tu placa y el PIN de cuatro a seis dígitos.',
                  style: body(size: 13, color: C.mutedDim)),
              Gap.h24,
              OField(label: 'Placa del empleado', hint: 'EMP-0142', controller: _badge),
              Gap.h16,
              OLabel('PIN'),
              Gap.h8,
              Row(
                children: List.generate(
                  6,
                  (i) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      width: 22,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i < _pin.length ? C.green.withOpacity(0.18) : C.surface,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: i < _pin.length ? C.green : C.line),
                      ),
                      child: Text(i < _pin.length ? '•' : '',
                          style: mono(size: 16, color: C.green, weight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              _keypad(),
              Gap.h12,
              OButton(
                label: _working ? 'Abriendo turno…' : 'Abrir turno',
                onTap: _working || _pin.length < 4 ? null : _enter,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keypad() => GridView.count(
        shrinkWrap: true,
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.9,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9']) _key(d),
          const SizedBox.shrink(),
          _key('0'),
          _key('⌫', onTap: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1))),
        ],
      );

  Widget _key(String label, {VoidCallback? onTap}) => GestureDetector(
        onTap: onTap ?? () => _tap(label),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: C.line),
          ),
          child: Text(label, style: display(size: 22, weight: FontWeight.w600)),
        ),
      );
}
