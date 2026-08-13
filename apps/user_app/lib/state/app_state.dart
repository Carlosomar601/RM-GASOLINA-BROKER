import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/dto.dart';
import '../api/order_stream.dart';
import '../api/session_store.dart';
import '../data/mock_data.dart';
import '../data/repository.dart';
import '../models/models.dart';

/// Estado único de la app del cliente.
///
/// Un solo ChangeNotifier mantiene la sesión, el catálogo, la orden en curso
/// y el surtido. Habla siempre con un [Repository]: en modo demo es local,
/// con `--dart-define=OCTANO_API=…` es el broker real y los mismos métodos
/// pasan a ser llamadas HTTP + WebSocket.
class AppState extends ChangeNotifier {
  AppState({Repository? repository}) : repo = repository ?? createRepository();

  final Repository repo;

  bool get live => repo.isLive;

  // ── Sesión ──────────────────────────────────────────────────────────
  String customerName = 'Carlos Omar';
  String phone = '+1 (787) 555-0142';
  String email = 'carlos@retailmanagerpr.com';
  bool signedIn = false;
  bool photoVerified = true;
  double walletBalance = 42.60;
  String cardLast4 = '4417';

  Vehicle vehicle = const Vehicle(
    plate: 'HJK-482',
    make: 'Toyota Corolla 2021',
    color: 'Gris plata',
    tankLiters: 50,
  );

  // ── Catálogo ────────────────────────────────────────────────────────
  List<Station> stations = MockData.stations;
  List<Product> products = MockData.products;
  bool busy = false;
  String? error;

  // ── Orden en curso ──────────────────────────────────────────────────
  Station? station;
  FuelType fuelType = FuelType.regular;
  double fuelCap = 25; // techo autorizado en USD
  final List<CartLine> cart = [];
  int? pumpNumber;
  OrderStage stage = OrderStage.draft;
  String orderId = '';
  String orderCode = '';
  String edgeTxUuid = '';
  DateTime? authorizedAt;
  Receipt? receipt;

  // ── Surtido ─────────────────────────────────────────────────────────
  double dispensedAmount = 0;
  double dispensedVolume = 0;
  bool dispensing = false;
  bool streamConnected = false;
  Timer? _ticker;
  Timer? _poll;
  OrderStream? _stream;

  // ── Derivados ───────────────────────────────────────────────────────
  double get itemsTotal => cart.fold(0, (s, l) => s + l.total);
  double get authorizedHold => fuelCap + itemsTotal;
  double get pricePerLiter => station?.priceOf(fuelType) ?? 0.87;
  double get dispensedLiters =>
      dispensedVolume > 0 ? dispensedVolume : (pricePerLiter == 0 ? 0 : dispensedAmount / pricePerLiter);
  double get finalTotal => dispensedAmount + itemsTotal;
  double get releasedHold => max(0, authorizedHold - finalTotal);
  int get cartCount => cart.fold(0, (s, l) => s + l.qty);

  List<FuelType> get availableFuels => station?.availableFuels ?? FuelType.values.take(3).toList();

  List<Product> productsIn(ProductCategory? c) =>
      c == null ? products : products.where((p) => p.category == c).toList();

  /// Envuelve una llamada al broker: marca ocupado, captura el error del
  /// backend y deja la UI en un estado consistente.
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

  // ── Sesión ──────────────────────────────────────────────────────────
  /// Demo: entra directo. Broker: valida contra `/v1/auth/customer/login`.
  Future<bool> signIn({String? name, String? phone, String? password}) async {
    if (!live) {
      if (name != null && name.trim().isNotEmpty) customerName = name.trim();
      signedIn = true;
      notifyListeners();
      return true;
    }
    final s = await _guard(() => repo.signIn(
          phone: phone ?? this.phone,
          password: password ?? '',
        ));
    if (s == null) return false;
    signedIn = true;
    await SessionStore.save(token: s.token, customerId: s.customerId, expiresAt: s.expiresAt);
    await _loadProfile();
    await loadStations();
    return true;
  }

  Future<bool> register({
    required String fullName,
    required String phone,
    required String password,
    String? email,
    String? plate,
    String? vehicleName,
    String? color,
    double? tankLiters,
  }) async {
    if (!live) return signIn(name: fullName);
    final s = await _guard(() => repo.register(
          phone: phone,
          fullName: fullName,
          password: password,
          email: email,
          plate: plate,
          vehicle: vehicleName,
          color: color,
          tankLiters: tankLiters,
        ));
    if (s == null) return false;
    signedIn = true;
    await SessionStore.save(token: s.token, customerId: s.customerId, expiresAt: s.expiresAt);
    await _loadProfile();
    await loadStations();
    return true;
  }

  /// Arranque: reinstala el token guardado y verifica que siga vivo.
  /// Devuelve true si la app puede saltar directo a estaciones.
  Future<bool> restoreSession() async {
    if (!live) return false;
    final saved = await SessionStore.read();
    if (saved == null) return false;
    repo.restoreToken(saved.token);
    try {
      final p = await repo.me();
      if (p == null) return false;
      signedIn = true;
      _applyProfile(p);
      await loadStations();
      return true;
    } on ApiException {
      await SessionStore.clear();
      repo.restoreToken(null);
      return false;
    }
  }

  void signOut() {
    signedIn = false;
    repo.restoreToken(null);
    SessionStore.clear();
    resetOrder();
  }

  Future<void> _loadProfile() async {
    final p = await repo.me();
    if (p == null) return;
    _applyProfile(p);
  }

  void _applyProfile(Profile p) {
    customerName = p.fullName.isEmpty ? customerName : p.fullName;
    phone = p.phone.isEmpty ? phone : p.phone;
    email = p.email;
    walletBalance = p.balance;
    photoVerified = p.photoVerified;
    cardLast4 = p.cardLast4;
    if (p.vehicle != null) vehicle = p.vehicle!;
    notifyListeners();
  }

  Future<void> topUpWallet(double amount) async {
    if (!live) {
      walletBalance += amount;
      notifyListeners();
      return;
    }
    final b = await _guard(() => repo.topUp(amount));
    if (b != null) walletBalance = b;
  }

  // ── Catálogo ────────────────────────────────────────────────────────
  Future<void> loadStations() async {
    if (!live) return;
    final list = await _guard(() => repo.stations());
    if (list != null && list.isNotEmpty) stations = list;
  }

  Future<void> loadProducts(String stationId) async {
    if (!live) return;
    final list = await _guard(() => repo.products(stationId));
    if (list != null) products = list;
  }

  Future<List<PumpStatus>> loadPumps() async {
    final id = station?.id;
    if (id == null) return const [];
    return await _guard(() => repo.pumps(id)) ?? const [];
  }

  // ── Estación y combustible ─────────────────────────────────────────
  void selectStation(Station s) {
    station = s;
    if (!s.prices.containsKey(fuelType) && s.prices.isNotEmpty) fuelType = s.prices.keys.first;
    notifyListeners();
    if (live) loadProducts(s.id);
  }

  void setFuelType(FuelType t) {
    fuelType = t;
    notifyListeners();
  }

  void setFuelCap(double usd) {
    fuelCap = usd;
    notifyListeners();
  }

  void fillTank() {
    fuelCap = ((vehicle.tankLiters * pricePerLiter / 5).ceil() * 5).toDouble();
    notifyListeners();
  }

  // ── Carrito ────────────────────────────────────────────────────────
  int qtyOf(Product p) =>
      cart.firstWhere((l) => l.product.id == p.id, orElse: () => CartLine(product: p, qty: 0)).qty;

  void add(Product p, [int n = 1]) {
    final line = cart.where((l) => l.product.id == p.id).firstOrNull;
    if (line == null) {
      cart.add(CartLine(product: p, qty: n));
    } else {
      line.qty += n;
    }
    notifyListeners();
  }

  void remove(Product p) {
    final line = cart.where((l) => l.product.id == p.id).firstOrNull;
    if (line == null) return;
    line.qty -= 1;
    if (line.qty <= 0) cart.remove(line);
    notifyListeners();
  }

  void clearCart() {
    cart.clear();
    notifyListeners();
  }

  // ── Voz ────────────────────────────────────────────────────────────
  /// Interpretación local de la frase dictada: extrae monto de combustible,
  /// tipo y productos del minimarket. En producción esto lo resuelve el
  /// servicio de NLU y devuelve el mismo shape.
  VoiceParse parseVoice(String transcript) {
    final t = transcript.toLowerCase();
    double? amount;
    final m = RegExp(r'(\d{1,3})').firstMatch(t);
    if (m != null) amount = double.tryParse(m.group(1)!);
    amount ??= _wordAmount(t);
    if (t.contains('llena') || t.contains('full') || t.contains('tanque')) {
      amount = ((vehicle.tankLiters * pricePerLiter / 5).ceil() * 5).toDouble();
    }
    FuelType? type;
    if (t.contains('premium') || t.contains('93')) type = FuelType.premium;
    if (t.contains('diésel') || t.contains('diesel')) type = FuelType.diesel;
    if (t.contains('regular') || t.contains('87')) type = FuelType.regular;

    const keywords = {
      'café': 'Café',
      'cafe': 'Café',
      'espresso': 'Espresso',
      'agua': 'Agua',
      'refresco': 'Refresco',
      'malta': 'Malta',
      'sándwich': 'Sándwich',
      'sandwich': 'Sándwich',
      'papitas': 'Papitas',
      'barra': 'Barra',
      'hielo': 'Hielo',
      'aceite': 'Aceite',
      'cargador': 'Cargador',
    };
    final found = <Product>[];
    keywords.forEach((k, name) {
      if (t.contains(k)) {
        final p = _findProduct(name);
        if (p != null && !found.any((e) => e.id == p.id)) found.add(p);
      }
    });
    return VoiceParse(amount: amount, fuelType: type, products: found);
  }

  /// Busca en el catálogo cargado (broker) y cae al de demo si está vacío.
  Product? _findProduct(String fragment) {
    final f = fragment.toLowerCase();
    for (final p in products) {
      if (p.name.toLowerCase().contains(f)) return p;
    }
    return MockData.byName(fragment);
  }

  /// Números dictados en palabras (lo común en PR: «ponme veinte de regular»).
  // Orden importante: las claves largas primero («veinticinco» contiene «cinco»).
  static const _words = <String, double>{
    'setenta y cinco': 75,
    'veinticinco': 25,
    'cincuenta': 50,
    'cuarenta': 40,
    'sesenta': 60,
    'treinta': 30,
    'quince': 15,
    'veinte': 20,
    'cien': 100,
    'diez': 10,
    'cinco': 5,
  };

  double? _wordAmount(String t) {
    for (final e in _words.entries) {
      if (t.contains(e.key)) return e.value;
    }
    return null;
  }

  void applyVoice(VoiceParse parse) {
    if (parse.amount != null) fuelCap = parse.amount!.clamp(5.0, 200.0).toDouble();
    if (parse.fuelType != null) fuelType = parse.fuelType!;
    for (final p in parse.products) {
      add(p);
    }
    notifyListeners();
  }

  // ── Ciclo de vida de la orden ──────────────────────────────────────
  /// Crea la orden (si hace falta) y coloca la retención.
  /// Demo: genera código local. Broker: `POST /v1/orders` + `/authorize`.
  Future<bool> authorize() async {
    if (!live) {
      final r = Random();
      orderCode = 'OC-${2600 + r.nextInt(399)}';
      edgeTxUuid = _uuid(r);
      authorizedAt = DateTime.now();
      stage = OrderStage.authorized;
      notifyListeners();
      return true;
    }

    final s = station;
    if (s == null) {
      error = 'Escoge una estación antes de autorizar.';
      notifyListeners();
      return false;
    }

    final snap = await _guard(() async {
      final created = orderId.isEmpty
          ? await repo.createOrder(
              stationId: s.id,
              fuelCode: s.codeOf(fuelType),
              capAmount: fuelCap,
              items: [for (final l in cart) (itemCode: l.product.code, qty: l.qty)],
            )
          : await repo.order(orderId);
      return repo.authorize(created.id);
    });
    if (snap == null) return false;
    _absorb(snap);
    authorizedAt = DateTime.now();
    _openStream();
    return true;
  }

  /// «Estoy aquí»: identifica el surtidor y dispara FuelPumpAuthorize.
  Future<bool> arrive({int? pump, String? qrToken}) async {
    pumpNumber = pump ?? pumpNumber ?? 3;
    if (!live) {
      stage = OrderStage.arrived;
      notifyListeners();
      return true;
    }
    final snap = await _guard(() => repo.arrive(orderId, pumpNumber: pumpNumber, qrToken: qrToken));
    if (snap == null) return false;
    _absorb(snap);
    return true;
  }

  Future<void> cancelOrder({String reason = 'cliente'}) async {
    if (live && orderId.isNotEmpty) {
      final snap = await _guard(() => repo.cancel(orderId, reason: reason));
      if (snap != null) _absorb(snap);
    }
    resetOrder();
  }

  /// Demo: simula el caudal. Broker: escucha `dispensing_progress` del
  /// pumpPoller y sondea como respaldo.
  void startDispensing() {
    stage = OrderStage.dispensing;
    dispensing = true;
    if (!live) {
      dispensedAmount = 0;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 120), (t) {
        dispensedAmount += fuelCap / 90;
        if (dispensedAmount >= fuelCap) {
          dispensedAmount = fuelCap;
          stopDispensing();
        }
        notifyListeners();
      });
      notifyListeners();
      return;
    }
    _openStream();
    _startPolling();
    notifyListeners();
  }

  void stopDispensing() {
    _ticker?.cancel();
    _ticker = null;
    dispensing = false;
    notifyListeners();
  }

  /// Cierra la orden y trae el recibo del broker.
  Future<void> settle() async {
    stopDispensing();
    _poll?.cancel();
    if (live && orderId.isNotEmpty) {
      final r = await _guard(() => repo.receipt(orderId));
      if (r != null) {
        receipt = r;
        dispensedAmount = r.fuelAmount;
        dispensedVolume = r.liters;
      }
    }
    stage = OrderStage.settled;
    _closeStream();
    notifyListeners();
  }

  void resetOrder() {
    stopDispensing();
    _closeStream();
    _poll?.cancel();
    _poll = null;
    cart.clear();
    station = null;
    pumpNumber = null;
    dispensedAmount = 0;
    dispensedVolume = 0;
    fuelCap = 25;
    stage = OrderStage.draft;
    orderId = '';
    orderCode = '';
    edgeTxUuid = '';
    authorizedAt = null;
    receipt = null;
    notifyListeners();
  }

  // ── Tiempo real ─────────────────────────────────────────────────────
  void _absorb(OrderSnapshot s) {
    orderId = s.id;
    orderCode = s.code;
    edgeTxUuid = s.edgeTransactionUuid;
    stage = s.stage;
    if (s.pumpNumber != null) pumpNumber = s.pumpNumber;
    if (s.capAmount > 0) fuelCap = s.capAmount;
    dispensedAmount = s.dispensedAmount;
    dispensedVolume = s.dispensedVolume;
    dispensing = s.status == 'dispensing';
    notifyListeners();
  }

  void _openStream() {
    if (!live || orderId.isEmpty || _stream != null) return;
    final token = repo.token;
    if (token == null) return;
    _stream = OrderStream(
      token: token,
      orderId: orderId,
      onStatus: (c) {
        streamConnected = c;
        notifyListeners();
      },
      onEvent: (e) {
        switch (e.type) {
          case 'dispensing_progress':
            dispensedAmount = e.amount ?? dispensedAmount;
            dispensedVolume = e.volume ?? dispensedVolume;
            dispensing = true;
            stage = OrderStage.dispensing;
            break;
          case 'dispensing':
            stage = OrderStage.dispensing;
            dispensing = true;
            break;
          case 'dispensed':
          case 'settled':
            dispensing = false;
            stage = OrderStage.settled;
            break;
          case 'arrived':
            stage = OrderStage.arrived;
            break;
          case 'cancelled':
            dispensing = false;
            stage = OrderStage.draft;
            break;
          default:
            final st = e.status;
            if (st != null) {
              stage = OrderSnapshot.fromJson(<String, dynamic>{'id': orderId, 'status': st}).stage;
            }
        }
        notifyListeners();
      },
    )..connect();
  }

  void _closeStream() {
    _stream?.close();
    _stream = null;
    streamConnected = false;
  }

  /// Respaldo del WebSocket: relee la orden cada pocos segundos.
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(Duration(seconds: ApiConfig.pollSeconds), (t) async {
      if (!live || orderId.isEmpty) return;
      try {
        final s = await repo.order(orderId);
        _absorb(s);
        if (s.finished) {
          t.cancel();
          dispensing = false;
          notifyListeners();
        }
      } on ApiException {
        // silencioso: el sondeo no debe romper la pantalla
      }
    });
  }

  String _uuid(Random r) {
    const hex = '0123456789abcdef';
    String block(int n) => List.generate(n, (_) => hex[r.nextInt(16)]).join();
    return '${block(8)}-${block(4)}-4${block(3)}-a${block(3)}-${block(12)}';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _poll?.cancel();
    _closeStream();
    repo.dispose();
    super.dispose();
  }
}

class VoiceParse {
  const VoiceParse({this.amount, this.fuelType, this.products = const []});
  final double? amount;
  final FuelType? fuelType;
  final List<Product> products;
  bool get isEmpty => amount == null && fuelType == null && products.isEmpty;
}

/// Acceso al estado sin dependencias externas.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope no encontrado en el árbol');
    return scope!.notifier!;
  }

  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    return scope!.notifier!;
  }
}
