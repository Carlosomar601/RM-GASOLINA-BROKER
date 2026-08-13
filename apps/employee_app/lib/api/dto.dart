import '../models/models.dart';

/// Traductores entre el JSON del broker y los modelos del handheld.

double _d(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? fallback;
}

int _i(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? fallback;
}

/// `tasks.status` del broker → estado del handheld.
TaskStatus taskStatusFrom(String raw) => switch (raw) {
      'incoming' => TaskStatus.entrante,
      'accepted' => TaskStatus.aceptada,
      'picking' => TaskStatus.preparando,
      'waiting' => TaskStatus.esperando,
      'delivering' => TaskStatus.entregando,
      'escalated' => TaskStatus.escalada,
      'closed' => TaskStatus.cerrada,
      _ => TaskStatus.entrante,
    };

FuelGrade gradeFromCode(String code) {
  final c = code.toLowerCase();
  if (c.contains('93') || c.contains('prem')) return FuelGrade.p93;
  if (c.startsWith('d') || c.contains('dsl')) return FuelGrade.dsl;
  if (c.contains('lpg') || c.contains('glp')) return FuelGrade.lpg;
  return FuelGrade.r87;
}

int _minutesSince(dynamic iso) {
  final t = DateTime.tryParse('$iso');
  if (t == null) return 0;
  final m = DateTime.now().difference(t.toLocal()).inMinutes;
  return m < 0 ? 0 : m;
}

PickItem pickItemFromJson(Map<String, dynamic> j) => PickItem(
      id: '${j['id']}',
      itemCode: '${j['item_code'] ?? ''}',
      name: '${j['name']}',
      qty: _i(j['qty'], 1),
      aisle: '${j['aisle'] ?? 'Mostrador'}',
      unitPrice: _d(j['unit_price']),
      picked: j['picked_at'] != null,
      substituted: j['substituted'] == true,
      delivered: j['delivered_at'] != null,
    );

/// Fila de `/v1/tasks` (lista) o `/v1/tasks/:id` (detalle con artículos).
Task taskFromJson(Map<String, dynamic> j) {
  final items = (j['items'] as List? ?? const []).cast<Map<String, dynamic>>();
  return Task(
    id: '${j['id']}',
    orderId: '${j['order_id']}',
    code: '${j['code'] ?? ''}',
    customer: '${j['customer_name'] ?? 'Cliente'}',
    plate: '${j['plate'] ?? '—'}',
    vehicle: [j['make_model'], j['color']].where((e) => e != null && '$e'.isNotEmpty).join(' '),
    grade: gradeFromCode('${j['fuel_code'] ?? ''}'),
    fuelName: '${j['fuel_name'] ?? ''}',
    cap: _d(j['cap_amount']),
    itemsAmount: _d(j['items_amount']),
    dispensed: _d(j['dispensed_amount']),
    minutesAgo: _minutesSince(j['arrived_at'] ?? j['created_at']),
    status: taskStatusFrom('${j['status']}'),
    orderStatus: '${j['order_status'] ?? ''}',
    pump: j['pump_number'] == null ? null : _i(j['pump_number']),
    priority: j['priority'] == true,
    identityOk: j['identity_ok'] == true,
    photoUrl: j['photo_url'] == null ? null : '${j['photo_url']}',
    edgeTxUuid: '${j['edge_transaction_uuid'] ?? ''}',
    itemCount: _i(j['item_count'], items.length),
    items: items.map(pickItemFromJson).toList(),
  );
}

/// Sesión del empleado (`/v1/auth/employee/login`).
class EmployeeSession {
  const EmployeeSession({
    required this.token,
    required this.employeeId,
    required this.stationId,
    required this.role,
    this.expiresAt,
  });

  final String token;
  final String employeeId;
  final String stationId;
  final String role;
  final DateTime? expiresAt;

  factory EmployeeSession.fromJson(Map<String, dynamic> j) => EmployeeSession(
        token: '${j['token']}',
        employeeId: '${j['employeeId']}',
        stationId: '${j['stationId']}',
        role: '${j['role'] ?? 'attendant'}',
        expiresAt: DateTime.tryParse('${j['expiresAt']}'),
      );
}
