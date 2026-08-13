import 'package:flutter/material.dart';

/// Estado de una tarea en el handheld (espejo de order_lifecycle.status).
enum TaskStatus { entrante, aceptada, preparando, esperando, entregando, escalada, cerrada }

extension TaskStatusX on TaskStatus {
  String get label => switch (this) {
        TaskStatus.entrante => 'Entrante',
        TaskStatus.aceptada => 'Aceptada',
        TaskStatus.preparando => 'Preparando',
        TaskStatus.esperando => 'Esperando cliente',
        TaskStatus.entregando => 'Entregando',
        TaskStatus.escalada => 'Escalada',
        TaskStatus.cerrada => 'Cerrada',
      };

  /// Código que entiende el broker (`tasks.status`).
  String get code => switch (this) {
        TaskStatus.entrante => 'incoming',
        TaskStatus.aceptada => 'accepted',
        TaskStatus.preparando => 'picking',
        TaskStatus.esperando => 'waiting',
        TaskStatus.entregando => 'delivering',
        TaskStatus.escalada => 'escalated',
        TaskStatus.cerrada => 'closed',
      };

  Color get color => switch (this) {
        TaskStatus.entrante => const Color(0xFFF5A524),
        TaskStatus.aceptada => const Color(0xFF6EA8FE),
        TaskStatus.preparando => const Color(0xFF6EA8FE),
        TaskStatus.esperando => const Color(0xFFF5A524),
        TaskStatus.entregando => const Color(0xFF1FC16B),
        TaskStatus.escalada => const Color(0xFFE5484D),
        TaskStatus.cerrada => const Color(0xFF6B7775),
      };
}

enum FuelGrade { r87, p93, dsl, lpg }

extension FuelGradeX on FuelGrade {
  String get label => switch (this) {
        FuelGrade.r87 => 'Regular 87',
        FuelGrade.p93 => 'Premium 93',
        FuelGrade.dsl => 'Diésel',
        FuelGrade.lpg => 'Gas LP',
      };
  String get short => switch (this) {
        FuelGrade.r87 => '87',
        FuelGrade.p93 => '93',
        FuelGrade.dsl => 'DSL',
        FuelGrade.lpg => 'LPG',
      };
  Color get color => switch (this) {
        FuelGrade.r87 => const Color(0xFF1FC16B),
        FuelGrade.p93 => const Color(0xFFF5A524),
        FuelGrade.dsl => const Color(0xFF6EA8FE),
        FuelGrade.lpg => const Color(0xFFA78BFA),
      };
}

class PickItem {
  PickItem({
    required this.name,
    required this.qty,
    required this.aisle,
    this.id = '',
    this.itemCode = '',
    this.unitPrice = 0,
    this.picked = false,
    this.substituted = false,
    this.delivered = false,
  });

  /// `order_items.id` en el broker (vacío en los datos de demostración).
  final String id;
  final String itemCode;
  final String name;
  final int qty;
  final String aisle;
  final double unitPrice;
  bool picked;
  bool substituted;
  bool delivered;
}

class Task {
  Task({
    required this.code,
    required this.customer,
    required this.plate,
    required this.vehicle,
    required this.grade,
    required this.cap,
    required this.items,
    required this.minutesAgo,
    this.id = '',
    this.orderId = '',
    this.fuelName = '',
    this.itemsAmount = 0,
    this.orderStatus = '',
    this.identityOk = false,
    this.photoUrl,
    this.itemCount,
    this.status = TaskStatus.entrante,
    this.pump,
    this.dispensed = 0,
    this.priority = false,
    this.edgeTxUuid = '',
  });

  /// `tasks.id` y `orders.id` del broker.
  final String id;
  final String orderId;
  final String code;
  final String customer;
  final String plate;
  final String vehicle;
  final FuelGrade grade;
  final String fuelName;
  final double cap;
  final double itemsAmount;
  final List<PickItem> items;
  final int minutesAgo;
  final String orderStatus;
  final int? itemCount;
  final String? photoUrl;
  TaskStatus status;
  bool identityOk;
  int? pump;
  double dispensed;
  final bool priority;
  final String edgeTxUuid;

  /// Con el broker viene calculado; en demo se estima.
  double get itemsTotal =>
      itemsAmount > 0 ? itemsAmount : items.fold(0, (s, i) => s + i.qty * (i.unitPrice == 0 ? 2.5 : i.unitPrice));
  int get pickedCount => items.where((i) => i.picked).length;
  bool get allPicked => items.isEmpty || items.every((i) => i.picked);
  bool get hasItems => (itemCount ?? items.length) > 0;
}

class Employee {
  const Employee({
    required this.name,
    required this.role,
    required this.station,
    required this.badge,
    this.id = '',
    this.stationId = '',
  });
  final String id;
  final String stationId;
  final String name;
  final String role;
  final String station;
  final String badge;

  Employee copyWith({String? name, String? role, String? station, String? badge, String? id, String? stationId}) =>
      Employee(
        name: name ?? this.name,
        role: role ?? this.role,
        station: station ?? this.station,
        badge: badge ?? this.badge,
        id: id ?? this.id,
        stationId: stationId ?? this.stationId,
      );
}
