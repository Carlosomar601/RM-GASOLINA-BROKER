import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/dto.dart';
import '../models/models.dart';
import 'mock_tasks.dart';

/// Contrato del handheld contra el broker. Dos implementaciones: demo local
/// y broker real (`--dart-define=OCTANO_API=…`).
abstract class ShiftRepository {
  bool get isLive;
  String? get token;
  void restoreToken(String? value) {}

  Future<EmployeeSession> login({required String badge, required String pin});
  Future<List<Task>> tasks();
  Future<Task> task(String taskId);
  Future<TaskStatus> accept(String taskId);
  Future<void> pick(String taskId, String itemId, {bool picked = true, bool substituted = false});
  Future<TaskStatus> identity(String taskId, {required bool matches, String? note});
  Future<void> close(String taskId, {required double dispensedAmount, double? dispensedVolume});

  void dispose() {}
}

ShiftRepository createShiftRepository() =>
    ApiConfig.live ? ApiShiftRepository() : MockShiftRepository();

// ─────────────────────────────────────────────────────────────────────────

class ApiShiftRepository implements ShiftRepository {
  ApiShiftRepository({ApiClient? client}) : _c = client ?? ApiClient();

  final ApiClient _c;

  @override
  bool get isLive => true;

  @override
  String? get token => _c.token;

  @override
  void restoreToken(String? value) => _c.token = value;

  @override
  Future<EmployeeSession> login({required String badge, required String pin}) async {
    final s = EmployeeSession.fromJson(
      await _c.post('/v1/auth/employee/login', body: {'badge': badge, 'pin': pin}) as Map<String, dynamic>,
    );
    _c.token = s.token;
    return s;
  }

  @override
  Future<List<Task>> tasks() async =>
      ((await _c.get('/v1/tasks')) as List).cast<Map<String, dynamic>>().map(taskFromJson).toList();

  @override
  Future<Task> task(String taskId) async =>
      taskFromJson(await _c.get('/v1/tasks/$taskId') as Map<String, dynamic>);

  @override
  Future<TaskStatus> accept(String taskId) async {
    final j = await _c.post('/v1/tasks/$taskId/accept') as Map<String, dynamic>;
    return taskStatusFrom('${j['status']}');
  }

  @override
  Future<void> pick(String taskId, String itemId, {bool picked = true, bool substituted = false}) =>
      _c.post('/v1/tasks/$taskId/items/$itemId/pick', body: {'picked': picked, 'substituted': substituted});

  @override
  Future<TaskStatus> identity(String taskId, {required bool matches, String? note}) async {
    final j = await _c.post('/v1/tasks/$taskId/identity', body: {
      'matches': matches,
      if (note != null && note.isNotEmpty) 'note': note,
    }) as Map<String, dynamic>;
    return taskStatusFrom('${j['status']}');
  }

  @override
  Future<void> close(String taskId, {required double dispensedAmount, double? dispensedVolume}) => _c.post(
        '/v1/tasks/$taskId/close',
        body: {
          'dispensedAmount': dispensedAmount,
          if (dispensedVolume != null) 'dispensedVolume': dispensedVolume,
        },
      );

  @override
  void dispose() => _c.close();
}

// ─────────────────────────────────────────────────────────────────────────

class MockShiftRepository implements ShiftRepository {
  final List<Task> _tasks = MockTasks.seed();

  @override
  bool get isLive => false;

  @override
  String? get token => null;

  @override
  void restoreToken(String? value) {}

  @override
  Future<EmployeeSession> login({required String badge, required String pin}) async =>
      const EmployeeSession(token: 'demo', employeeId: 'demo', stationId: 'demo', role: 'attendant');

  @override
  Future<List<Task>> tasks() async => _tasks;

  @override
  Future<Task> task(String taskId) async => _tasks.firstWhere((t) => t.id == taskId);

  @override
  Future<TaskStatus> accept(String taskId) async {
    final t = await task(taskId);
    return t.hasItems ? TaskStatus.preparando : TaskStatus.esperando;
  }

  @override
  Future<void> pick(String taskId, String itemId, {bool picked = true, bool substituted = false}) async {}

  @override
  Future<TaskStatus> identity(String taskId, {required bool matches, String? note}) async =>
      matches ? TaskStatus.entregando : TaskStatus.escalada;

  @override
  Future<void> close(String taskId, {required double dispensedAmount, double? dispensedVolume}) async {}

  @override
  void dispose() {}
}
