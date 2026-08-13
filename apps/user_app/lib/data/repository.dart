import 'dart:async';
import 'dart:math';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/dto.dart';
import '../models/models.dart';
import 'mock_data.dart';

/// Sesión abierta: token del broker + identidad del cliente.
class Session {
  const Session({required this.token, required this.customerId, required this.expiresAt});
  final String token;
  final String customerId;
  final DateTime? expiresAt;
}

/// Contrato único que consume `AppState`. Dos implementaciones:
/// `MockRepository` (demo, sin red) y `ApiRepository` (broker real).
abstract class Repository {
  bool get isLive;

  Future<Session> signIn({required String phone, required String password});
  Future<Session> register({
    required String phone,
    required String fullName,
    required String password,
    String? email,
    String? plate,
    String? vehicle,
    String? color,
    double? tankLiters,
  });

  Future<Profile?> me();
  Future<List<Station>> stations();
  Future<List<Product>> products(String stationId);
  Future<List<PumpStatus>> pumps(String stationId);
  Future<double> topUp(double amount);

  Future<OrderSnapshot> createOrder({
    required String stationId,
    required String fuelCode,
    required double capAmount,
    required List<({String itemCode, int qty})> items,
  });
  Future<OrderSnapshot> authorize(String orderId);
  Future<OrderSnapshot> arrive(String orderId, {int? pumpNumber, String? qrToken});
  Future<OrderSnapshot> cancel(String orderId, {String reason});
  Future<OrderSnapshot> order(String orderId);
  Future<Receipt> receipt(String orderId);

  String? get token;

  /// Reinstala un token guardado (sesión restaurada al arrancar).
  void restoreToken(String? value) {}

  void dispose() {}
}

Repository createRepository() => ApiConfig.live ? ApiRepository() : MockRepository();

// ─────────────────────────────────────────────────────────────────────────
// Broker real
// ─────────────────────────────────────────────────────────────────────────

class ApiRepository implements Repository {
  ApiRepository({ApiClient? client}) : _c = client ?? ApiClient();

  final ApiClient _c;

  @override
  bool get isLive => true;

  @override
  String? get token => _c.token;

  @override
  void restoreToken(String? value) => _c.token = value;

  Session _session(Map<String, dynamic> j) {
    final s = Session(
      token: '${j['token']}',
      customerId: '${j['customerId']}',
      expiresAt: DateTime.tryParse('${j['expiresAt']}'),
    );
    _c.token = s.token;
    return s;
  }

  @override
  Future<Session> signIn({required String phone, required String password}) async => _session(
        await _c.post('/v1/auth/customer/login', body: {'phone': phone, 'password': password})
            as Map<String, dynamic>,
      );

  @override
  Future<Session> register({
    required String phone,
    required String fullName,
    required String password,
    String? email,
    String? plate,
    String? vehicle,
    String? color,
    double? tankLiters,
  }) async =>
      _session(
        await _c.post('/v1/auth/customer/register', body: {
          'phone': phone,
          'fullName': fullName,
          'password': password,
          if (email != null && email.isNotEmpty) 'email': email,
          if (plate != null && plate.isNotEmpty) 'plate': plate,
          if (vehicle != null && vehicle.isNotEmpty) 'vehicle': vehicle,
          if (color != null && color.isNotEmpty) 'color': color,
          if (tankLiters != null) 'tankLiters': tankLiters,
        }) as Map<String, dynamic>,
      );

  @override
  Future<Profile?> me() async => Profile.fromJson((await _c.get('/v1/me')) as Map<String, dynamic>);

  @override
  Future<List<Station>> stations() async => ((await _c.get('/v1/stations')) as List)
      .cast<Map<String, dynamic>>()
      .map(stationFromJson)
      .toList();

  @override
  Future<List<Product>> products(String stationId) async =>
      ((await _c.get('/v1/stations/$stationId/products')) as List)
          .cast<Map<String, dynamic>>()
          .map(productFromJson)
          .toList();

  @override
  Future<List<PumpStatus>> pumps(String stationId) async =>
      ((await _c.get('/v1/stations/$stationId/pumps')) as List)
          .cast<Map<String, dynamic>>()
          .map(PumpStatus.fromJson)
          .toList();

  @override
  Future<double> topUp(double amount) async {
    final j = await _c.post('/v1/me/wallet/topup', body: {'amount': amount}) as Map<String, dynamic>;
    return (j['balance'] as num?)?.toDouble() ?? 0;
  }

  @override
  Future<OrderSnapshot> createOrder({
    required String stationId,
    required String fuelCode,
    required double capAmount,
    required List<({String itemCode, int qty})> items,
  }) async =>
      OrderSnapshot.fromJson(await _c.post('/v1/orders', body: {
        'stationId': stationId,
        'fuelCode': fuelCode,
        'capAmount': capAmount,
        'items': [
          for (final i in items) {'itemCode': i.itemCode, 'qty': i.qty},
        ],
      }) as Map<String, dynamic>);

  @override
  Future<OrderSnapshot> authorize(String orderId) async =>
      OrderSnapshot.fromJson(await _c.post('/v1/orders/$orderId/authorize') as Map<String, dynamic>);

  @override
  Future<OrderSnapshot> arrive(String orderId, {int? pumpNumber, String? qrToken}) async =>
      OrderSnapshot.fromJson(await _c.post('/v1/orders/$orderId/arrive', body: {
        if (qrToken != null) 'qrToken': qrToken else 'pumpNumber': pumpNumber,
      }) as Map<String, dynamic>);

  @override
  Future<OrderSnapshot> cancel(String orderId, {String reason = 'cliente'}) async =>
      OrderSnapshot.fromJson(
          await _c.post('/v1/orders/$orderId/cancel', body: {'reason': reason}) as Map<String, dynamic>);

  @override
  Future<OrderSnapshot> order(String orderId) async =>
      OrderSnapshot.fromJson(await _c.get('/v1/orders/$orderId') as Map<String, dynamic>);

  @override
  Future<Receipt> receipt(String orderId) async =>
      Receipt.fromJson(await _c.get('/v1/orders/$orderId/receipt') as Map<String, dynamic>);

  @override
  void dispose() => _c.close();
}

// ─────────────────────────────────────────────────────────────────────────
// Demo local (mockups): mismas firmas, sin red
// ─────────────────────────────────────────────────────────────────────────

class MockRepository implements Repository {
  final _r = Random();
  final Map<String, _MockOrder> _orders = {};

  @override
  bool get isLive => false;

  @override
  String? get token => null;

  @override
  Future<Session> signIn({required String phone, required String password}) async =>
      Session(token: 'demo', customerId: 'demo', expiresAt: null);

  @override
  Future<Session> register({
    required String phone,
    required String fullName,
    required String password,
    String? email,
    String? plate,
    String? vehicle,
    String? color,
    double? tankLiters,
  }) async =>
      Session(token: 'demo', customerId: 'demo', expiresAt: null);

  @override
  Future<Profile?> me() async => null; // el AppState conserva sus valores de demo

  @override
  Future<List<Station>> stations() async => MockData.stations;

  @override
  Future<List<Product>> products(String stationId) async => MockData.products;

  @override
  Future<List<PumpStatus>> pumps(String stationId) async => List.generate(
        8,
        (i) => PumpStatus(number: i + 1, status: 'idle', busy: i == 2 || i == 5),
      );

  @override
  Future<double> topUp(double amount) async => amount;

  @override
  Future<OrderSnapshot> createOrder({
    required String stationId,
    required String fuelCode,
    required double capAmount,
    required List<({String itemCode, int qty})> items,
  }) async {
    final o = _MockOrder(
      id: 'demo-${_r.nextInt(99999)}',
      code: 'OC-${2600 + _r.nextInt(399)}',
      stationId: stationId,
      fuelCode: fuelCode,
      capAmount: capAmount,
    );
    _orders[o.id] = o;
    return o.snapshot();
  }

  @override
  Future<OrderSnapshot> authorize(String orderId) async => _patch(orderId, 'authorized');

  @override
  Future<OrderSnapshot> arrive(String orderId, {int? pumpNumber, String? qrToken}) async {
    final o = _orders[orderId]!;
    o.pumpNumber = pumpNumber ?? 3;
    return _patch(orderId, 'arrived');
  }

  @override
  Future<OrderSnapshot> cancel(String orderId, {String reason = 'cliente'}) async =>
      _patch(orderId, 'cancelled');

  @override
  Future<OrderSnapshot> order(String orderId) async => _orders[orderId]!.snapshot();

  @override
  Future<Receipt> receipt(String orderId) async {
    final o = _orders[orderId]!;
    return Receipt(
      code: o.code,
      station: 'Octano',
      pump: o.pumpNumber,
      fuel: o.fuelCode,
      pricePerLiter: 0.87,
      liters: o.capAmount / 0.87,
      fuelAmount: o.capAmount,
      itemsAmount: 0,
      total: o.capAmount,
      released: 0,
      edgeTransactionUuid: o.id,
      rmInvoiceNumber: null,
    );
  }

  OrderSnapshot _patch(String id, String status) {
    final o = _orders[id]!;
    o.status = status;
    return o.snapshot();
  }
}

class _MockOrder {
  _MockOrder({
    required this.id,
    required this.code,
    required this.stationId,
    required this.fuelCode,
    required this.capAmount,
  });

  final String id;
  final String code;
  final String stationId;
  final String fuelCode;
  final double capAmount;
  String status = 'draft';
  int? pumpNumber;

  OrderSnapshot snapshot() => OrderSnapshot(
        id: id,
        code: code,
        status: status,
        edgeTransactionUuid: id,
        stationId: stationId,
        fuelCode: fuelCode,
        pricePerLiter: 0.87,
        capAmount: capAmount,
        itemsAmount: 0,
        authorizedAmount: capAmount,
        dispensedAmount: 0,
        dispensedVolume: 0,
        finalAmount: 0,
        releasedAmount: 0,
        pumpNumber: pumpNumber,
      );
}
