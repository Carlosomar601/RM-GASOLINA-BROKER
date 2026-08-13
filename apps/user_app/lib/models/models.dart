import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum FuelType { regular, premium, diesel, lpg }

extension FuelTypeX on FuelType {
  String get label => switch (this) {
        FuelType.regular => 'Regular 87',
        FuelType.premium => 'Premium 93',
        FuelType.diesel => 'Diésel',
        FuelType.lpg => 'Gas LP',
      };

  String get short => switch (this) {
        FuelType.regular => '87',
        FuelType.premium => '93',
        FuelType.diesel => 'DSL',
        FuelType.lpg => 'LPG',
      };

  Color get color => switch (this) {
        FuelType.regular => C.green,
        FuelType.premium => C.amber,
        FuelType.diesel => const Color(0xFF6EA8FE),
        FuelType.lpg => const Color(0xFFA78BFA),
      };
}

class Station {
  const Station({
    required this.id,
    required this.name,
    required this.brand,
    required this.address,
    required this.town,
    required this.distanceKm,
    required this.open,
    required this.pumps,
    required this.prices,
    this.waitMinutes = 3,
    this.hasMinimarket = true,
    this.fuelCodes = const {},
    this.lat,
    this.lng,
  });

  final String id;
  final String name;
  final String brand;
  final String address;
  final String town;
  final double distanceKm;
  final bool open;
  final int pumps;
  final Map<FuelType, double> prices; // USD por litro
  final int waitMinutes;
  final bool hasMinimarket;

  /// Código real del grado en el broker (`fuel_products.code`) por tipo.
  final Map<FuelType, String> fuelCodes;
  final double? lat;
  final double? lng;

  List<FuelType> get availableFuels =>
      prices.keys.isEmpty ? const [FuelType.regular] : prices.keys.toList();

  double priceOf(FuelType t) =>
      prices[t] ?? (prices.isEmpty ? 0 : prices.values.first);

  /// `r87` por defecto si la estación no declaró código para ese grado.
  String codeOf(FuelType t) =>
      fuelCodes[t] ??
      switch (t) {
        FuelType.regular => 'r87',
        FuelType.premium => 'p93',
        FuelType.diesel => 'dsl',
        FuelType.lpg => 'lpg',
      };
}

enum ProductCategory { bebidas, snacks, cafe, auto, esenciales }

extension ProductCategoryX on ProductCategory {
  String get label => switch (this) {
        ProductCategory.bebidas => 'Bebidas',
        ProductCategory.snacks => 'Snacks',
        ProductCategory.cafe => 'Café',
        ProductCategory.auto => 'Auto',
        ProductCategory.esenciales => 'Esenciales',
      };
}

class Product {
  const Product({
    required this.id,
    this.itemCode = '',
    required this.name,
    required this.detail,
    required this.price,
    required this.category,
    this.inStock = true,
  });

  final String id;

  /// `products.item_code` — la referencia que viaja al POS de Retail Manager.
  final String itemCode;
  final String name;
  final String detail;
  final double price;
  final ProductCategory category;
  final bool inStock;

  String get code => itemCode.isEmpty ? id : itemCode;
}

class CartLine {
  CartLine({required this.product, this.qty = 1});
  final Product product;
  int qty;
  double get total => product.price * qty;
}

/// Etapas del ciclo de vida de la orden (espejo del schema:
/// order_lifecycle.status).
enum OrderStage { draft, authorized, arrived, dispensing, settled }

extension OrderStageX on OrderStage {
  String get label => switch (this) {
        OrderStage.draft => 'Borrador',
        OrderStage.authorized => 'Autorizada',
        OrderStage.arrived => 'En estación',
        OrderStage.dispensing => 'Surtiendo',
        OrderStage.settled => 'Liquidada',
      };
}

class Vehicle {
  const Vehicle({
    required this.plate,
    required this.make,
    required this.color,
    required this.tankLiters,
  });
  final String plate;
  final String make;
  final String color;
  final double tankLiters;
}
