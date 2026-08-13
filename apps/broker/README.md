# Octano Broker

API de nube entre las apps móviles (cliente y empleado) y los dos sistemas que
ya existen: **Retail Manager** (API v2 `cse.api.v1`, POSDPS/FDLink) y el
**PTS-2** a través de **PTS2Link**.

```
Flutter USER APP ─┐
                  ├─► BROKER (este servicio) ─► Retail Manager API  (catálogo, precios, factura)
Flutter EMPLOYEE ─┘         │                └─► PTS2Link ─► PTS-2 ─► bombas y sondas
                            └─► Postgres (orden, retención, trazabilidad)
```

El broker **no** reimplementa PTS2Link ni el POS. Es dueño de: cuenta del
cliente, cartera, orden, retención de tarjeta, tarea del handheld, bitácora y
la cola de salida hacia Retail Manager.

**Multi-cliente desde el diseño.** Un solo broker atiende a varios operadores
(tenants), cada uno con varias estaciones, y **cada estación con su propio
Retail Manager, su propio PTS2Link y sus propias reglas** (IVU, techo,
vida de la retención, serie de factura). Nada de eso vive en el `.env`: vive
en la tabla `integrations` y se administra por API. Añadir un cliente nuevo
es crear tenant → estación → enlaces, sin redeployar.

---

## Instalar

Descomprime en `D:\PROGRAMACION CARLOS OMAR\RM GASOLINA\BROKER`, luego:

```powershell
cd "D:\PROGRAMACION CARLOS OMAR\RM GASOLINA\BROKER"
copy .env.example .env      # ajusta RM_API_BASE, PTS2LINK_BASE, DATABASE_URL
npm install
docker compose up -d db     # o usa tu Postgres existente
npm run migrate             # crea el esquema
npm run seed                # semilla con el PTS-2 real (4 bombas, 3 tanques)
npm run dev                 # http://localhost:8090/health
```

Requiere Node 20.11+ y Postgres 15+.

---

## Añadir un cliente nuevo (multi-tenant)

```http
POST /v1/admin/tenants        { "code": "GASOMAX", "name": "Gasomax PR" }
POST /v1/admin/stations       { "tenantId": "...", "code": "GX-01", "name": "Gasomax Ponce" }
POST /v1/admin/integrations   { "tenantId": "...", "stationId": "...", "kind": "rm_api",
                                "label": "RM Ponce", "baseUrl": "http://10.0.0.21:8180",
                                "authType": "query", "username": "2", "secret": "•••",
                                "settings": { "userId": "2", "channel": 1,
                                              "pathPrefix": "cse.api.v1",
                                              "fuelProductCode": "FUEL" } }
POST /v1/admin/integrations   { ..., "kind": "pts2link", "baseUrl": "http://10.0.0.30:9080",
                                "settings": { "paths": { "pumps": "/api/pumps",
                                              "pumpStatus": "/api/pumps/{pump}/status",
                                              "tanks": "/api/tanks" } } }
POST /v1/admin/integrations/:id/test        # prueba real y guarda el resultado
PUT  /v1/admin/stations/:id/rules           # IVU, techo, TTL de retención, serie de factura
GET  /v1/admin/stations/:id/effective-config
PATCH /v1/admin/stations/:id                { "status": "active" }
```

Detalles que importan:

- **Rutas configurables**: las de PTS2Link se declaran en
  `integrations.settings.paths` (con `{pump}` como variable), así cada build
  puede exponer paths distintos. Las de RM se ajustan con
  `settings.pathPrefix` (por omisión `cse.api.v1`).
- **Secretos cifrados** con AES-256-GCM (`MASTER_KEY`); la API nunca los
  devuelve, sólo `hasSecret` y los últimos 4.
- **Resolución en cascada**: enlace de la estación → enlace por omisión del
  tenant (`station_id` NULL) → `.env` (solo desarrollo). Caché de 30 s que se
  invalida al guardar.
- **Aislamiento**: `GET /v1/stations` sólo devuelve estaciones del tenant del
  cliente autenticado; el outbox y el poller trabajan estación por estación,
  así un POS caído no arrastra a los demás.
- **IVU por estación**: `station_rules` (PR sembrado con 10.5% estatal + 1%
  municipal, combustible exento) y el outbox calcula `StateTax`/`CityTax` de
  la factura con esas tasas.

## Base de datos

`db/migrations/001_init.sql` + `003_multitenant.sql` — 31 tablas + 3 vistas:

| Dominio | Tablas |
|---|---|
| Identidad y cartera | `customers`, `customer_devices`, `vehicles`, `wallets`, `wallet_entries` |
| Estación y físico | `stations`, `controllers`, `fuel_products`, `tanks`, `tank_readings`, `pumps`, `hoses`, `fuel_prices` |
| Catálogo | `products` (espejo de solo lectura del POS) |
| Personal | `employees`, `shifts` |
| Orden | `orders`, `order_items`, `order_events` |
| Pagos | `payment_methods`, `payment_holds` |
| Cumplimiento | `tasks` |
| Integración | `rm_outbox`, `pts_commands`, `audit_log` |
| Multi-tenant | `tenants`, `integrations`, `station_rules`, `console_users`, `integration_events` |

Claves de diseño:

- **`orders.edge_transaction_uuid`** es la clave de correlación de punta a
  punta y también el `RequestId` que se manda a `FuelPumpAuthorize`
  (idempotencia real: reintentar no autoriza dos veces).
- El **precio se congela** en `orders.price_per_unit` al autorizar; `fuel_prices`
  guarda el histórico espejado desde `FDPrecios` vía `FuelPrices`.
- `pumps`/`hoses`/`tanks` guardan **ambos identificadores**: el de Retail
  Manager (`rm_pump_id`, `rm_hose_id`, `rm_tank_id`) y el del PTS
  (`pts_pump_number`, `pts_nozzle_number`, `pts_tank_number`), igual que los
  mapeos de PTS2Link.
- Nada se escribe en el POS de forma directa: todo pasa por `rm_outbox` con
  reintentos y backoff, así una caída de RM no rompe el cierre de la orden.

## Flujo de una orden

| Paso | Endpoint | Qué hace |
|---|---|---|
| 1 | `POST /v1/orders` | borrador: estación, grado, techo, artículos |
| 2 | `POST /v1/orders/:id/authorize` | **retención** = techo + minimarket (no cobra) |
| 3 | `POST /v1/orders/:id/arrive` | QR o número de surtidor → `FuelPumpAuthorize` a RM con `RequestId` + crea la tarea del handheld |
| 4 | *worker* | `PTS2Link` reporta `FILLING` → `dispensing` + progreso en vivo por WebSocket |
| 5 | *worker* | `END_OF_TRANSACTION` → captura la retención, libera la diferencia, encola la factura |
| 6 | `GET /v1/orders/:id/receipt` | recibo con `edge_transaction_uuid` y número de factura RM |

Respaldo manual: `POST /v1/tasks/:id/close` con el monto real, para cuando el
pulso del surtidor no llega.

## Endpoints

**Cliente** (`Authorization: Bearer <jwt>`)
`POST /v1/auth/customer/register` · `POST /v1/auth/customer/login` ·
`GET /v1/me` · `POST /v1/me/wallet/topup` · `GET /v1/stations` ·
`GET /v1/stations/:id/products` · `GET /v1/stations/:id/pumps` ·
`POST /v1/orders` · `POST /v1/orders/:id/authorize` ·
`POST /v1/orders/:id/arrive` · `POST /v1/orders/:id/cancel` ·
`GET /v1/orders` · `GET /v1/orders/:id` · `GET /v1/orders/:id/receipt`

**Empleado**
`POST /v1/auth/employee/login` · `GET /v1/tasks` · `GET /v1/tasks/:id` ·
`POST /v1/tasks/:id/accept` · `POST /v1/tasks/:id/items/:itemId/pick` ·
`POST /v1/tasks/:id/identity` · `POST /v1/tasks/:id/close`

**Operación** (con `x-admin-token` si `ADMIN_TOKEN` está puesto)
`GET /health` · `GET /v1/admin/links` · `GET /v1/admin/overview?stationId=` ·
`GET /v1/admin/orders` · `GET /v1/admin/orders/:id/events` · `GET /v1/admin/audit` ·
`GET /v1/admin/stations/:id/rm/ping` · `GET /v1/admin/stations/:id/pts/status` ·
`GET /v1/admin/stations/:id/mappings` · `GET /v1/admin/stations/:id/effective-config` ·
`POST /v1/admin/stations/:id/sync-prices` · `POST /v1/stations/:id/sync-products` ·
`POST /v1/admin/outbox/retry`

**Multi-tenant**
`GET|POST /v1/admin/tenants` · `GET|POST /v1/admin/stations` ·
`PATCH /v1/admin/stations/:id` · `GET|PUT /v1/admin/stations/:id/rules` ·
`GET|POST /v1/admin/integrations` · `PUT|DELETE /v1/admin/integrations/:id` ·
`POST /v1/admin/integrations/:id/test` · `GET /v1/admin/integrations/:id/events`

**Tiempo real**
`ws://host:8090/v1/stream?token=<jwt>` y luego
`{"subscribe":"order","id":"<uuid>"}` o `{"subscribe":"station","id":"<uuid>"}`.

## Integración con Retail Manager

`src/clients/rmApi.ts` — base `RM_API_BASE` + `/cse.api.v1/`:
`ServerTime`, `Validez`, `ValidateUser`, `GetAllProducts`, `ProductInfo`,
`FuelPrices`, `FuelTanks`, `FuelPumpStatus`, `FuelRequestStatus`,
`FuelPumpAuthorize`, `FuelSetPrice`, `ImportExternalInvoice`.

Ojo (lo dice la propia colección): los endpoints `Fuel*` requieren el esquema
FDLink nuevo y columnas de `FDPrecios`. Verifica con
`GET /v1/admin/rm/ping` y `GET /v1/admin/pts/status` antes de una prueba en pista.

## Integración con el PTS-2

- Camino normal: **PTS2Link** (`src/clients/ptsLink.ts`). Ajusta las rutas del
  objeto `paths` si tu build expone otros paths.
- Respaldo/diagnóstico: **jsonPTS directo** (`src/clients/jsonPts.ts`) con
  Digest y **validación de huella TLS SHA-256** — no desactiva TLS. Apagado por
  defecto (`PTS_DIRECT_ENABLED=false`); sólo hace consultas.
- La semilla refleja el controlador real `192.168.100.251`: 4 bombas en el
  puerto 1, mangueras 1-3 → grados 1 Petrol / 2 Diesel / 3 LPG, tanques 1-3 con
  sondas 1-3. La sonda 4 del puerto `DISP` **no** se mapea (uso desconocido).

## Pendiente / decisiones abiertas

- Procesador de pagos real: implementa `HoldProvider` en `src/domain/payments.ts`
  (`place`/`capture`/`release`) y cambia `provider`. También puede pasar a ser
  una integración por tenant (`kind='payments'`, ya reservado en el esquema).
- Rutas reales del API de PTS2Link: se cargan por estación en
  `settings.paths` — con darme una, quedan todas.
- `ProductCode` de la línea de combustible: hoy sale de `fuel_products.rm_product_id`
  o de `settings.fuelProductCode` (`'FUEL'` por omisión), configurable por estación.
- Consola web del panel admin (hoy sólo API) y login de `console_users`.
- Notificaciones push (FCM) y OTP por SMS para el registro.
- Endurecer `/v1/admin/*` con token de servicio o VPN.
