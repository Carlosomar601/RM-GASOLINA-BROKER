import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/api/dto.dart';
import 'package:user_app/app.dart';
import 'package:user_app/models/models.dart';
import 'package:user_app/state/app_state.dart';

void main() {
  test('la retención cubre techo + minimarket y libera la diferencia', () {
    final s = AppState();
    s.setFuelCap(30);
    expect(s.authorizedHold, 30);
    s.dispensedAmount = 21.40;
    expect(s.finalTotal, closeTo(21.40, 0.001));
    expect(s.releasedHold, closeTo(8.60, 0.001));
  });

  test('la voz extrae monto, tipo y productos', () {
    final s = AppState();
    final p = s.parseVoice('Ponme veinte dólares de premium y un café con leche');
    expect(p.amount, 20);
    expect(p.fuelType!.name, 'premium');
    expect(p.products.length, 1);
  });

  testWidgets('la app arranca en el login', (tester) async {
    await tester.pumpWidget(const OctanoApp());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Entrar'), findsOneWidget);
  });

  test('los códigos de grado del broker se mapean a FuelType', () {
    expect(fuelTypeFromCode('r87'), FuelType.regular);
    expect(fuelTypeFromCode('p93'), FuelType.premium);
    expect(fuelTypeFromCode('dsl'), FuelType.diesel);
    expect(fuelTypeFromCode('lpg'), FuelType.lpg);
  });

  test('la estación del broker conserva el código real del grado', () {
    final st = stationFromJson({
      'id': '1111',
      'code': 'OCT-01',
      'name': 'Octano Isla Verde',
      'address': 'Ave. Isla Verde',
      'town': 'Carolina',
      'is_open': true,
      'pumps': 4,
      'fuels': [
        {'code': 'r87', 'name': 'Regular 87', 'pricePerLiter': '0.87'},
        {'code': 'lpg', 'name': 'Gas LP', 'pricePerLiter': 1.45},
      ],
    });
    expect(st.availableFuels.length, 2);
    expect(st.priceOf(FuelType.regular), closeTo(0.87, 0.001));
    expect(st.codeOf(FuelType.lpg), 'lpg');
  });

  test('la orden del broker se traduce a etapa de la app', () {
    final o = OrderSnapshot.fromJson({
      'id': 'o-1',
      'code': 'OC-2601',
      'status': 'dispensing',
      'edgeTransactionUuid': 'abc',
      'station': {'id': 's-1'},
      'fuel': {'code': 'r87', 'pricePerLiter': 0.87},
      'capAmount': 25,
      'dispensedAmount': '12.50',
      'dispensedVolume': 14.3,
      'pumpNumber': 3,
    });
    expect(o.stage, OrderStage.dispensing);
    expect(o.dispensedAmount, closeTo(12.5, 0.001));
    expect(o.pumpNumber, 3);
  });
}
