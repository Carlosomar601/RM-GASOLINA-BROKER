import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../api/dto.dart';
import '../api/session_store.dart';
import '../api/station_stream.dart';
import '../data/mock_tasks.dart';
import '../data/repository.dart';
import '../models/models.dart';

/// Estado del turno en el handheld: cola de tareas, tarea activa y métricas.
///
/// Habla siempre con un [ShiftRepository]. En demo la cola es local; con
/// `--dart-define=OCTANO_API=…` la cola viene de `/v1/tasks` y se refresca
/// sola con los eventos de estación del broker.
class ShiftState extends ChangeNotifier {
  ShiftState({ShiftRepository? repository}) : repo = repository ?? createShiftRepository();

  final ShiftRepository repo;

  bool get live => repo.isLive;

  Employee employee = const Employee(
    name: 'Luis Martínez',
    role: 'Atendiente de pista',
    station: 'Octano Isla Verde',
    badge: 'EMP-0142',
  );

  bool signedIn = false;
  bool shiftOpen = true;
  bool pumpsOnline = true;
  bool cloudOnline = true;
  bool streamConnected = false;
  bool busy = false;
  String? error;

  int servedToday = 34;
  double volumeToday = 1284.5;
  double avgMinutes = 4.2;

  List<Task> tasks = MockTasks.seed();
  Task? active;

  StationStream? _stream;
  Timer? _poll;

  List<Task> get incoming => tasks.where((t) => t.status == TaskStatus.entrante).toList();
  List<Task> get openTasks => tasks.where((t) => t.status != TaskStatus.cerrada).toList();
  int get pendingCount => openTasks.length;

  Future<T?> _guard<T>(Future<T> Function() run) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      return await run();
    } on ApiException catch (e) {
      error = e.message;
      return null;
    } catch (e) {
      error = '$e';
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (error == null) return;
    error = null;
    notifyListeners();
  }

  // ── Turno ───────────────────────────────────────────────────────────
  /// Entrada por placa + PIN. En demo entra directo.
  Future<bool> signIn({required String badge, required String pin}) async {
    if (!live) {
      signedIn = true;
      notifyListeners();
      return true;
    }
    final s = await _guard(() => repo.login(badge: badge, pin: pin));
    if (s == null) return false;
    await SessionStore.save(
      token: s.token,
      employeeId: s.employeeId,
      stationId: s.stationId,
      role: s.role,
      expiresAt: s.expiresAt,
    );
    _adopt(s, badge: badge);
    await refresh();
    _openStream();
    return true;
  }

  /// Reinstala el turno guardado al abrir la app.
  Future<bool> restoreSession() async {
    if (!live) return false;
    final saved = await SessionStore.read();
    if (saved == null) return false;
    repo.restoreToken(saved.token);
    try {
      tasks = await repo.tasks();
      signedIn = true;
      employee = employee.copyWith(id: saved.employeeId, stationId: saved.stationId, role: _roleLabel(saved.role));
      cloudOnline = true;
      _openStream();
      notifyListeners();
      return true;
    } on ApiException {
      await SessionStore.clear();
      repo.restoreToken(null);
      return false;
    }
  }

  void signOut() {
    signedIn = false;
    active = null;
    _closeStream();
    _poll?.cancel();
    repo.restoreToken(null);
    SessionStore.clear();
    notifyListeners();
  }

  void _adopt(EmployeeSession s, {required String badge}) {
    employee = employee.copyWith(
      id: s.employeeId,
      stationId: s.stationId,
      badge: badge.toUpperCase(),
      role: _roleLabel(s.role),
    );
  }

  static String _roleLabel(String role) => switch (role) {
        'attendant' => 'Atendiente de pista',
        'cashier' => 'Cajero',
        'supervisor' => 'Supervisor',
        'manager' => 'Gerente',
        _ => role,
      };

  // ── Cola ────────────────────────────────────────────────────────────
  Future<void> refresh() async {
    if (!live) return;
    final list = await _guard(() => repo.tasks());
    if (list == null) {
      cloudOnline = false;
      notifyListeners();
      return;
    }
    cloudOnline = true;
    tasks = list;
    if (active != null) {
      final same = list.where((t) => t.id == active!.id).toList();
      active = same.isEmpty ? null : same.first;
    }
    notifyListeners();
  }

  /// Trae el detalle (artículos) de la tarea antes de abrir picking/entrega.
  Future<void> select(Task t) async {
    active = t;
    notifyListeners();
    if (!live || t.id.isEmpty) return;
    final full = await _guard(() => repo.task(t.id));
    if (full == null) return;
    active = full;
    tasks = [for (final x in tasks) if (x.id == full.id) full else x];
    notifyListeners();
  }

  Future<void> accept(Task t) async {
    if (!live) {
      t.status = t.items.isEmpty ? TaskStatus.esperando : TaskStatus.preparando;
      active = t;
      notifyListeners();
      return;
    }
    final status = await _guard(() => repo.accept(t.id));
    if (status == null) return;
    t.status = status;
    active = t;
    await select(t);
  }

  Future<void> togglePick(PickItem i) async {
    i.picked = !i.picked;
    notifyListeners();
    final t = active;
    if (!live || t == null || i.id.isEmpty) return;
    final ok = await _guard(() async {
      await repo.pick(t.id, i.id, picked: i.picked, substituted: i.substituted);
      return true;
    });
    if (ok == null) {
      i.picked = !i.picked; // el broker mandó: revertimos
      notifyListeners();
    }
  }

  Future<void> substitute(PickItem i) async {
    i.substituted = true;
    i.picked = true;
    notifyListeners();
    final t = active;
    if (!live || t == null || i.id.isEmpty) return;
    await _guard(() async {
      await repo.pick(t.id, i.id, picked: true, substituted: true);
      return true;
    });
  }

  /// Fin del picking: en el broker el paso siguiente lo abre la verificación
  /// de identidad, así que aquí solo movemos la tarjeta.
  void readyForDelivery(Task t) {
    t.status = TaskStatus.entregando;
    notifyListeners();
  }

  /// Verificación de identidad por foto antes de entregar.
  Future<bool> verifyIdentity(Task t, {required bool matches, String? note}) async {
    if (!live) {
      t.identityOk = matches;
      t.status = matches ? TaskStatus.entregando : TaskStatus.escalada;
      notifyListeners();
      return matches;
    }
    final status = await _guard(() => repo.identity(t.id, matches: matches, note: note));
    if (status == null) return false;
    t.identityOk = matches;
    t.status = status;
    notifyListeners();
    return matches;
  }

  /// Cierre manual del surtido (respaldo cuando el pulso del PTS-2 no llega).
  Future<bool> close(Task t, {double? dispensed}) async {
    final amount = dispensed ?? t.cap;
    if (!live) {
      _closeLocally(t, amount);
      return true;
    }
    final ok = await _guard(() async {
      await repo.close(t.id, dispensedAmount: amount);
      return true;
    });
    if (ok == null) return false;
    _closeLocally(t, amount);
    await refresh();
    return true;
  }

  void _closeLocally(Task t, double amount) {
    t.dispensed = amount;
    t.status = TaskStatus.cerrada;
    servedToday += 1;
    volumeToday += amount / 0.87;
    active = null;
    notifyListeners();
  }

  // ── Tiempo real ─────────────────────────────────────────────────────
  void _openStream() {
    if (!live || _stream != null) return;
    final token = repo.token;
    final stationId = employee.stationId;
    if (token == null || stationId.isEmpty) return;
    _stream = StationStream(
      token: token,
      stationId: stationId,
      onStatus: (c) {
        streamConnected = c;
        notifyListeners();
      },
      onEvent: (_) => refresh(),
    )..connect();

    // Respaldo: relee la cola cada 20 s aunque el socket esté vivo.
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => refresh());
  }

  void _closeStream() {
    _stream?.close();
    _stream = null;
    streamConnected = false;
  }

  // ── Ajustes del turno ───────────────────────────────────────────────
  void toggleShift() {
    shiftOpen = !shiftOpen;
    notifyListeners();
  }

  void setRole(String role) {
    employee = employee.copyWith(role: role);
    notifyListeners();
  }

  void toggleCloud() {
    cloudOnline = !cloudOnline;
    notifyListeners();
  }

  void togglePumps() {
    pumpsOnline = !pumpsOnline;
    notifyListeners();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _closeStream();
    repo.dispose();
    super.dispose();
  }
}

class ShiftScope extends InheritedNotifier<ShiftState> {
  const ShiftScope({super.key, required ShiftState state, required super.child})
      : super(notifier: state);

  static ShiftState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShiftScope>()!.notifier!;

  static ShiftState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShiftScope>()!.notifier!;
}
