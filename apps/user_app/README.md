# Octano · App del cliente (Flutter)

App móvil del cliente para el flujo de combustible prepago con entrega al carro:
**login → cartera → estaciones → minimarket → voz → combustible → retención → llegada → surtido → recibo → perfil**.

Corresponde 1:1 con las 11 pantallas del tablero de mockups (`Fuel and Go+ Mockups.dc.html`).

---

## Instalar en tu máquina

1. Descomprime este contenido en:

   ```
   D:\PROGRAMACION CARLOS OMAR\RM GASOLINA\USER APP
   ```

   Debe quedar así: `USER APP\pubspec.yaml`, `USER APP\lib\...`

2. Genera las carpetas nativas (android/ios/windows). Desde esa carpeta:

   ```powershell
   cd "D:\PROGRAMACION CARLOS OMAR\RM GASOLINA\USER APP"
   flutter create . --project-name user_app --platforms=android,ios,windows
   flutter pub get
   ```

   `flutter create .` **no borra** `lib/` ni `pubspec.yaml`: solo agrega lo que falta.
   Si pregunta por sobrescribir `pubspec.yaml`, di no (o restaura el nuestro).

3. Corre:

   ```powershell
   flutter run                 # dispositivo/emulador Android
   flutter run -d windows      # escritorio, útil para iterar rápido
   ```

Requisitos: Flutter 3.19+ / Dart 3.3+.

---

## Estructura

```
lib/
  main.dart                 punto de entrada
  app.dart                  MaterialApp, rutas nombradas, Wordmark
  theme/
    tokens.dart             paleta (#15191B, #1FC16B, #F5A524, #F3F1EA), radios, gaps
    typography.dart         Space Grotesk / Hanken Grotesk / JetBrains Mono + ThemeData
  models/models.dart        Station, Product, CartLine, FuelType, OrderStage, Vehicle
  api/
    api_config.dart         URL del broker por --dart-define, armado de URLs REST/WS
    api_client.dart         HTTP con bearer, timeouts y ApiException normalizada
    dto.dart                JSON del broker → Station/Product/OrderSnapshot/Profile/Receipt
    order_stream.dart       WebSocket /v1/stream suscrito a la orden, con reconexión
  data/mock_data.dart       estaciones, catálogo y frases de voz de demostración
  data/repository.dart      Repository + MockRepository (demo) + ApiRepository (broker)
  services/speech_service.dart  dictado con el reconocedor del sistema (es-PR) + respaldo simulado
  widgets/qr_scanner.dart   hoja de escáneo del QR del surtidor (mobile_scanner)
  state/app_state.dart      AppState (ChangeNotifier) + AppScope (InheritedNotifier)
  widgets/ui.dart           OButton, OCard, OField, OHeader, ORow, OPill, OMoney, OStepper
  screens/                  11 pantallas, una por archivo
```

Sin gestor de estado externo: `AppState` + `AppScope.of(context)`.
Dependencias de terceros: `google_fonts`, `http`, `web_socket_channel`,
`shared_preferences`, `mobile_scanner`, `speech_to_text`.

---

## Permisos nativos

Después de `flutter create .`, añade a mano:

**`android/app/src/main/AndroidManifest.xml`** (dentro de `<manifest>`):

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

**`ios/Runner/Info.plist`**:

```xml
<key>NSCameraUsageDescription</key>
<string>Para escanear el QR del surtidor.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Para pedir combustible y artículos por voz.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Para entender tu pedido dictado.</string>
```

Sin cámara o sin micrófono la app no se rompe: el escáner ofrece escoger el
surtidor por número y el dictado cae a la frase simulada.

### QR del surtidor

El código pegado en la bomba debe contener el `pumps.qr_token` del broker.
Si además incluye el número (`octano://pump/3`, `surtidor-3`), la pantalla lo
resalta en la cuadrícula. El broker acepta `qrToken` o `pumpNumber` en
`POST /v1/orders/:id/arrive`.

---

## Modo demo vs. broker real

La app arranca en **modo demo** (datos de `mock_data.dart`, surtido simulado) mientras
no se le pase una URL. Para hablar con el broker:

```powershell
flutter run --dart-define=OCTANO_API=http://192.168.100.20:8080
```

| Define | Para qué |
|---|---|
| `OCTANO_API` | URL base del broker. Vacío = modo demo. |
| `OCTANO_STATION` | UUID de estación por defecto (pruebas de campo). |
| `OCTANO_POLL` | Segundos entre sondeos de respaldo del surtido (3 por defecto). |

En modo broker cambia el comportamiento, no las pantallas:

| Acción en la app | Llamada al broker |
|---|---|
| Entrar | `POST /v1/auth/customer/login` → token bearer |
| Crear cuenta | `POST /v1/auth/customer/register` (PIN = últimos 4 del teléfono) |
| Estaciones / precios | `GET /v1/stations` |
| Minimarket | `GET /v1/stations/:id/products` |
| Recargar cartera | `POST /v1/me/wallet/topup` |
| Autorizar | `POST /v1/orders` + `POST /v1/orders/:id/authorize` |
| «Estoy aquí» | `POST /v1/orders/:id/arrive` (dispara `FuelPumpAuthorize`) |
| Surtido en vivo | `ws /v1/stream` → `dispensing_progress`, con sondeo `GET /v1/orders/:id` |
| Recibo | `GET /v1/orders/:id/receipt` |

El surtido **no se simula** en modo broker: los litros y el monto vienen del
`pumpPoller`, que lee el controlador PTS2. Si el WebSocket se cae, el sondeo HTTP
mantiene la pantalla viva y el WebSocket reconecta con retroceso exponencial.

## Rutas

| Ruta | Pantalla |
|---|---|
| `/` | Iniciar sesión |
| `/crear-cuenta` | Crear cuenta + abrir cartera (2 pasos) |
| `/estaciones` | Balance, voz, estaciones cercanas |
| `/catalogo` | Minimarket de la estación |
| `/voz` | Compra por voz (dictado simulado + interpretación) |
| `/combustible` | Tipo + techo autorizado |
| `/autorizacion` | Retención de tarjeta |
| `/llegada` | «Estoy aquí» · QR o surtidor |
| `/surtiendo` | Contador en vivo |
| `/recibo` | Liquidación + `edge_transaction_uuid` |
| `/perfil` | Identidad por foto, vehículo, pagos |

## Reglas de negocio ya implementadas

- **Retención, no cobro**: `authorizedHold = techo + minimarket`; al cerrar se cobra
  `finalTotal = dispensado + minimarket` y se libera `releasedHold`.
- **Precio por litro** por estación y por tipo de combustible (PR vende por litro).
- **Surtido simulado** con un `Timer` a 120 ms; `stopDispensing()` corta antes del techo.
- **Trazabilidad**: cada orden genera `orderCode` y `edgeTransactionUuid`, el mismo
  campo de correlación del schema (`Client App Schema.dc.html`).
- **Llenar tanque**: techo = litros del tanque × precio, redondeado a $5.

## Lo que falta para producción

- Tokenización de tarjeta y autorización real (retención) con el procesador.
- NLU en servidor: hoy el dictado es real pero el parseo de la frase es local.
- Foto de verificación: cámara, subida y firma para la app del empleado.
- Push de estados cuando la app está en segundo plano (hoy WebSocket en primer plano).
- Español/Inglés con `flutter_localizations` (hoy los textos están en línea, en español).
