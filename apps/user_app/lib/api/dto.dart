import '../models/models.dart';

/// Traductores entre el JSON del broker y los modelos de la app.
/// El broker es la fuente de verdad: aquí no se inventan valores, sólo se
/// normaliza (nulos, números en texto, códigos de grado).

double _d(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? fallback;
}

int? _i(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

/// `r87` · `p93` · `dsl` · `lpg` — los códigos de `fuel_products.code`.
FuelType fuelTypeFromCode(String code) {
  final c = code.toLowerCase();
  if (c.contains('93') || c.contains('prem')) return FuelType.premium;
  if (c.startsWith('d') || c.contains('dsl')) return FuelType.diesel;
  if (c.contains('lpg') || c.contains('glp') || c.contains('gas lic')) return FuelType.lpg;
  return FuelType.regular;
}

String fuelCodeOf(FuelType t) => switch (t) {
      FuelType.regular => 'r87',
      FuelType.premium => 'p93',
      FuelType.diesel => 'dsl',
      FuelType.lpg => 'lpg',
    };

ProductCategory categoryFrom(String? raw) {
  final c = (raw ?? '').toLowerCase();
  if (c.contains('café') || c.contains('cafe')) return ProductCategory.cafe;
  if (c.contains('bebi') || c.contains('drink')) return ProductCategory.bebidas;
  if (c.contains('snack') || c.contains('comida')) return ProductCategory.snacks;
  if (c.contains('auto') || c.contains('lubric')) return ProductCategory.auto;
  return ProductCategory.esenciales;
}

Station stationFromJson(Map<String, dynamic> j) {
  final fuels = (j['fuels'] as List? ?? const []).cast<Map<String, dynamic>>();
  return Station(
    id: '${j['id']}',
    name: '${j['name']}',
    brand: '${j['code'] ?? 'Octano'}',
    address: '${j['address'] ?? ''}',
    town: '${j['town'] ?? ''}',
    distanceKm: _d(j['distanceKm']),
    open: j['is_open'] == true || j['isOpen'] == true,
    pumps: _i(j['pumps']) ?? 0,
    hasMinimarket: j['has_minimarket'] != false,
    prices: {
      for (final f in fuels) fuelTypeFromCode('${f['code']}'): _d(f['pricePerLiter']),
    },
    fuelCodes: {
      for (final f in fuels) fuelTypeFromCode('${f['code']}'): '${f['code']}',
    },
    lat: j['lat'] == null ? null : _d(j['lat']),
    lng: j['lng'] == null ? null : _d(j['lng']),
  );
}

Product productFromJson(Map<String, dynamic> j) => Product(
      id: '${j['id']}',
      itemCode: '${j['item_code'] ?? j['itemCode'] ?? ''}',
      name: '${j['name']}',
      detail: '${j['detail'] ?? j['aisle'] ?? ''}',
      price: _d(j['price']),
      category: categoryFrom('${j['category']}'),
      inStock: j['in_stock'] != false,
    );

/// Estado de un surtidor tal como lo ve el cliente al llegar.
class PumpStatus {
  const PumpStatus({required this.number, required this.status, required this.busy});
  final int number;
  final String status;
  final bool busy;

  bool get free => !busy && (status == 'idle' || status == 'ready' || status == 'free');

  factory PumpStatus.fromJson(Map<String, dynamic> j) => PumpStatus(
        number: _i(j['number']) ?? 0,
        status: '${j['status'] ?? 'unknown'}',
        busy: j['busy'] == true,
      );
}

/// Vista canónica de la orden (`fetchOrder` del broker).
class OrderSnapshot {
  const OrderSnapshot({
    required this.id,
    required this.code,
    required this.status,
    required this.edgeTransactionUuid,
    required this.stationId,
    required this.fuelCode,
    required this.pricePerLiter,
    required this.capAmount,
    required this.itemsAmount,
    required this.authorizedAmount,
    required this.dispensedAmount,
    required this.dispensedVolume,
    required this.finalAmount,
    required this.releasedAmount,
    this.pumpNumber,
  });

  final String id;
  final String code;
  final String status;
  final String edgeTransactionUuid;
  final String stationId;
  final String fuelCode;
  final double pricePerLiter;
  final double capAmount;
  final double itemsAmount;
  final double authorizedAmount;
  final double dispensedAmount;
  final double dispensedVolume;
  final double finalAmount;
  final double releasedAmount;
  final int? pumpNumber;

  OrderStage get stage => switch (status) {
        'authorized' => OrderStage.authorized,
        'arrived' => OrderStage.arrived,
        'dispensing' => OrderStage.dispensing,
        'dispensed' || 'settled' => OrderStage.settled,
        _ => OrderStage.draft,
      };

  bool get finished => status == 'settled' || status == 'dispensed';

  factory OrderSnapshot.fromJson(Map<String, dynamic> j) {
    final fuel = (j['fuel'] as Map?)?.cast<String, dynamic>() ?? const {};
    final station = (j['station'] as Map?)?.cast<String, dynamic>() ?? const {};
    return OrderSnapshot(
      id: '${j['id']}',
      code: '${j['code'] ?? ''}',
      status: '${j['status'] ?? 'draft'}',
      edgeTransactionUuid: '${j['edgeTransactionUuid'] ?? ''}',
      stationId: '${station['id'] ?? ''}',
      fuelCode: '${fuel['code'] ?? 'r87'}',
      pricePerLiter: _d(fuel['pricePerLiter']),
      capAmount: _d(j['capAmount']),
      itemsAmount: _d(j['itemsAmount']),
      authorizedAmount: _d(j['authorizedAmount']),
      dispensedAmount: _d(j['dispensedAmount']),
      dispensedVolume: _d(j['dispensedVolume']),
      finalAmount: _d(j['finalAmount']),
      releasedAmount: _d(j['releasedAmount']),
      pumpNumber: _i(j['pumpNumber']),
    );
  }
}

/// Perfil + cartera + vehículos (`GET /v1/me`).
class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.balance,
    required this.photoVerified,
    required this.vehicle,
    required this.cardLast4,
  });

  final String id;
  final String fullName;
  final String phone;
  final String email;
  final double balance;
  final bool photoVerified;
  final Vehicle? vehicle;
  final String cardLast4;

  factory Profile.fromJson(Map<String, dynamic> j) {
    final vehicles = (j['vehicles'] as List? ?? const []).cast<Map<String, dynamic>>();
    final cards = (j['paymentMethods'] as List? ?? const []).cast<Map<String, dynamic>>();
    final v = vehicles.where((e) => e['is_default'] == true).firstOrNull ?? vehicles.firstOrNull;
    final card = cards.where((e) => e['is_default'] == true).firstOrNull ?? cards.firstOrNull;
    return Profile(
      id: '${j['id']}',
      fullName: '${j['full_name'] ?? ''}',
      phone: '${j['phone'] ?? ''}',
      email: '${j['email'] ?? ''}',
      balance: _d(j['balance']),
      photoVerified: j['photo_verified_at'] != null,
      vehicle: v == null
          ? null
          : Vehicle(
              plate: '${v['plate']}',
              make: '${v['make_model'] ?? ''}',
              color: '${v['color'] ?? ''}',
              tankLiters: _d(v['tank_liters'], 50),
            ),
      cardLast4: '${card?['last4'] ?? '••••'}',
    );
  }
}

/// Recibo final (`GET /v1/orders/:id/receipt`).
class Receipt {
  const Receipt({
    required this.code,
    required this.station,
    required this.pump,
    required this.fuel,
    required this.pricePerLiter,
    required this.liters,
    required this.fuelAmount,
    required this.itemsAmount,
    required this.total,
    required this.released,
    required this.edgeTransactionUuid,
    required this.rmInvoiceNumber,
  });

  final String code;
  final String station;
  final int? pump;
  final String fuel;
  final double pricePerLiter;
  final double liters;
  final double fuelAmount;
  final double itemsAmount;
  final double total;
  final double released;
  final String edgeTransactionUuid;
  final String? rmInvoiceNumber;

  factory Receipt.fromJson(Map<String, dynamic> j) => Receipt(
        code: '${j['code'] ?? ''}',
        station: '${j['station'] ?? ''}',
        pump: _i(j['pump']),
        fuel: '${j['fuel'] ?? ''}',
        pricePerLiter: _d(j['pricePerLiter']),
        liters: _d(j['liters']),
        fuelAmount: _d(j['fuelAmount']),
        itemsAmount: _d(j['itemsAmount']),
        total: _d(j['total']),
        released: _d(j['released']),
        edgeTransactionUuid: '${j['edgeTransactionUuid'] ?? ''}',
        rmInvoiceNumber: j['rmInvoiceNumber'] == null ? null : '${j['rmInvoiceNumber']}',
      );
}

extension FirstOrNullX<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
