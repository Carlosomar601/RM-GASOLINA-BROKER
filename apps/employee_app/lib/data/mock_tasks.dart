import '../models/models.dart';

/// Cola de demostración del handheld: la misma que se presentó en los
/// mockups. En modo broker no se usa.
class MockTasks {
  MockTasks._();

  static List<Task> seed() => [
        Task(
          id: 'demo-1',
          orderId: 'demo-o1',
          code: 'OC-2841',
          customer: 'Carlos Omar',
          plate: 'HJK-482',
          vehicle: 'Toyota Corolla gris',
          grade: FuelGrade.r87,
          cap: 30,
          minutesAgo: 1,
          pump: 3,
          status: TaskStatus.entrante,
          edgeTxUuid: 'a91f4c02-77b1-4c93-a5de-0f19c7bb2d41',
          items: [
            PickItem(id: 'i1', name: 'Café con leche 16 oz', qty: 1, aisle: 'Barra', unitPrice: 2.75),
            PickItem(id: 'i2', name: 'Papitas clásicas', qty: 2, aisle: 'P3', unitPrice: 1.75),
          ],
        ),
        Task(
          id: 'demo-2',
          orderId: 'demo-o2',
          code: 'OC-2839',
          customer: 'Marisol Vega',
          plate: 'GTR-119',
          vehicle: 'Honda CR-V blanca',
          grade: FuelGrade.p93,
          cap: 50,
          minutesAgo: 3,
          pump: 5,
          status: TaskStatus.preparando,
          priority: true,
          edgeTxUuid: 'c47b2210-0d51-4a8e-b0ac-91ce4d33f7a2',
          items: [
            PickItem(id: 'i3', name: 'Agua 1 L', qty: 2, aisle: 'N1', unitPrice: 1.50, picked: true),
            PickItem(id: 'i4', name: 'Sándwich de jamón', qty: 1, aisle: 'Barra', unitPrice: 4.50),
          ],
        ),
        Task(
          id: 'demo-3',
          orderId: 'demo-o3',
          code: 'OC-2836',
          customer: 'Pedro Santiago',
          plate: 'FAB-703',
          vehicle: 'Ford F-150 negra',
          grade: FuelGrade.dsl,
          cap: 75,
          minutesAgo: 6,
          pump: 8,
          status: TaskStatus.esperando,
          edgeTxUuid: '5d80aa71-9b3c-4f22-8e6d-2a71b0cc9915',
          items: [],
        ),
        Task(
          id: 'demo-4',
          orderId: 'demo-o4',
          code: 'OC-2830',
          customer: 'Ana Robles',
          plate: 'KLM-224',
          vehicle: 'Kia Soul azul',
          grade: FuelGrade.r87,
          cap: 20,
          minutesAgo: 12,
          pump: 2,
          status: TaskStatus.cerrada,
          dispensed: 18.40,
          edgeTxUuid: '77c1e5b9-4a20-4d18-9f31-6b3f0a2e1c58',
          items: [PickItem(id: 'i5', name: 'Hielo 5 lb', qty: 1, aisle: 'Congelador', unitPrice: 3.50, picked: true)],
        ),
      ];
}
