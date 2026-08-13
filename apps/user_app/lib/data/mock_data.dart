import '../models/models.dart';

/// Datos de demostración. Cuando exista el API real, este archivo se sustituye
/// por un repositorio HTTP con la misma firma.
class MockData {
  MockData._();

  static const stations = <Station>[
    Station(
      id: 'st-101',
      name: 'Octano Isla Verde',
      brand: 'Octano',
      address: 'Ave. Isla Verde 5900',
      town: 'Carolina',
      distanceKm: 1.2,
      open: true,
      pumps: 8,
      waitMinutes: 2,
      prices: {
        FuelType.regular: 0.87,
        FuelType.premium: 0.99,
        FuelType.diesel: 0.94,
      },
    ),
    Station(
      id: 'st-102',
      name: 'Octano Hato Rey',
      brand: 'Octano',
      address: 'Ave. Ponce de León 1250',
      town: 'San Juan',
      distanceKm: 3.8,
      open: true,
      pumps: 6,
      waitMinutes: 5,
      prices: {
        FuelType.regular: 0.85,
        FuelType.premium: 0.97,
        FuelType.diesel: 0.92,
      },
    ),
    Station(
      id: 'st-103',
      name: 'Octano Bayamón Centro',
      brand: 'Octano',
      address: 'Carr. 167 Km 4.1',
      town: 'Bayamón',
      distanceKm: 9.4,
      open: true,
      pumps: 10,
      waitMinutes: 8,
      prices: {
        FuelType.regular: 0.84,
        FuelType.premium: 0.95,
        FuelType.diesel: 0.90,
      },
    ),
    Station(
      id: 'st-104',
      name: 'Octano Caguas Sur',
      brand: 'Octano',
      address: 'Ave. Rafael Cordero 210',
      town: 'Caguas',
      distanceKm: 14.1,
      open: false,
      pumps: 6,
      hasMinimarket: false,
      prices: {
        FuelType.regular: 0.86,
        FuelType.premium: 0.98,
        FuelType.diesel: 0.93,
      },
    ),
  ];

  static const products = <Product>[
    Product(
        id: 'p-01',
        name: 'Café con leche 16 oz',
        detail: 'Recién colado',
        price: 2.75,
        category: ProductCategory.cafe),
    Product(
        id: 'p-02',
        name: 'Espresso doble',
        detail: 'Para llevar',
        price: 3.25,
        category: ProductCategory.cafe),
    Product(
        id: 'p-03',
        name: 'Agua 1 L',
        detail: 'Fría',
        price: 1.50,
        category: ProductCategory.bebidas),
    Product(
        id: 'p-04',
        name: 'Refresco 20 oz',
        detail: 'Surtido',
        price: 2.25,
        category: ProductCategory.bebidas),
    Product(
        id: 'p-05',
        name: 'Malta fría',
        detail: '12 oz',
        price: 1.95,
        category: ProductCategory.bebidas),
    Product(
        id: 'p-06',
        name: 'Sándwich de jamón',
        detail: 'Pan sobao',
        price: 4.50,
        category: ProductCategory.snacks),
    Product(
        id: 'p-07',
        name: 'Papitas clásicas',
        detail: 'Bolsa 2.5 oz',
        price: 1.75,
        category: ProductCategory.snacks),
    Product(
        id: 'p-08',
        name: 'Barra de proteína',
        detail: 'Chocolate',
        price: 2.95,
        category: ProductCategory.snacks),
    Product(
        id: 'p-09',
        name: 'Aceite 10W-40',
        detail: '1 cuarto',
        price: 8.95,
        category: ProductCategory.auto),
    Product(
        id: 'p-10',
        name: 'Líquido limpiaparabrisas',
        detail: '1 galón',
        price: 4.25,
        category: ProductCategory.auto,
        inStock: false),
    Product(
        id: 'p-11',
        name: 'Hielo 5 lb',
        detail: 'Bolsa',
        price: 3.50,
        category: ProductCategory.esenciales),
    Product(
        id: 'p-12',
        name: 'Cargador USB-C',
        detail: '20 W',
        price: 12.99,
        category: ProductCategory.esenciales),
  ];

  /// Frases de ejemplo para la demo de compra por voz.
  static const voiceSamples = <String>[
    'Ponme veinte dólares de regular y un café con leche',
    'Llena el tanque de premium y dos aguas frías',
    'Quince de regular, papitas y una malta',
  ];

  static Product? byName(String fragment) {
    final f = fragment.toLowerCase();
    for (final p in products) {
      if (p.name.toLowerCase().contains(f)) return p;
    }
    return null;
  }
}
