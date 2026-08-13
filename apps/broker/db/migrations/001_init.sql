-- ════════════════════════════════════════════════════════════════════
-- Octano · esquema base
-- Postgres 15+. Fuente autorizada de precios e inventario: Retail Manager
-- (POSDPS). Fuente autorizada de volumen y estado de bomba: PTS-2 vía
-- PTS2Link. Este esquema es la orden, el pago y la trazabilidad.
-- ════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ── Identidad y cartera ──────────────────────────────────────────────

CREATE TABLE customers (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone             text NOT NULL UNIQUE,
  full_name         text NOT NULL,
  email             text,
  password_hash     text,
  photo_url         text,
  photo_verified_at timestamptz,
  rm_client_number  text,                 -- FDClientes.Number si se espeja al POS
  status            text NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active','blocked','deleted')),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE customer_devices (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id  uuid NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  platform     text NOT NULL CHECK (platform IN ('android','ios')),
  push_token   text,
  device_name  text,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (customer_id, push_token)
);

CREATE TABLE vehicles (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  plate       text NOT NULL,
  make_model  text,
  color       text,
  tank_liters numeric(6,2),
  is_default  boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (customer_id, plate)
);

CREATE TABLE wallets (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL UNIQUE REFERENCES customers(id) ON DELETE CASCADE,
  balance     numeric(12,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
  currency    char(3) NOT NULL DEFAULT 'USD',
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE wallet_entries (
  id           bigserial PRIMARY KEY,
  wallet_id    uuid NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
  kind         text NOT NULL CHECK (kind IN ('topup','charge','refund','adjust')),
  amount       numeric(12,2) NOT NULL,      -- + entra, - sale
  balance_after numeric(12,2) NOT NULL,
  order_id     uuid,
  memo         text,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX wallet_entries_wallet_idx ON wallet_entries (wallet_id, created_at DESC);

-- ── Estación, controlador y catálogo físico ──────────────────────────

CREATE TABLE stations (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code           text NOT NULL UNIQUE,     -- ST-101
  name           text NOT NULL,
  address        text,
  town           text,
  lat            numeric(9,6),
  lng            numeric(9,6),
  timezone       text NOT NULL DEFAULT 'America/Puerto_Rico',
  has_minimarket boolean NOT NULL DEFAULT true,
  is_open        boolean NOT NULL DEFAULT true,
  rm_api_base    text,                     -- http://host:8180
  pts2link_base  text,                     -- http://host:9080
  created_at     timestamptz NOT NULL DEFAULT now()
);

-- Controlador PTS-2 tal como lo registra PTS2Link (FDControllers)
CREATE TABLE controllers (
  id              int PRIMARY KEY,          -- mismo Id que usa PTS2Link / ControllerId de RM
  station_id      uuid NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
  name            text NOT NULL,
  host            text NOT NULL,
  port            int NOT NULL DEFAULT 443,
  protocol        text NOT NULL DEFAULT 'https' CHECK (protocol IN ('http','https')),
  auth_mode       text NOT NULL DEFAULT 'digest' CHECK (auth_mode IN ('none','basic','digest')),
  pts_unique_id   text,
  tls_fingerprint text,                     -- SHA-256 fijada
  firmware        text,
  enabled         boolean NOT NULL DEFAULT true,
  last_seen_at    timestamptz
);

-- Producto de combustible: puente entre FDFuelProducts y el grado PTS
CREATE TABLE fuel_products (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  station_id      uuid NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
  code            text NOT NULL,            -- 'r87' | 'p93' | 'dsl'
  display_name    text NOT NULL,            -- 'Regular 87'
  rm_product_id   int,                      -- FDFuelProducts.ID
  pts_grade_id    int NOT NULL,             -- grado PTS (1 Petrol, 2 Diesel, 3 LPG…)
  unit            text NOT NULL DEFAULT 'L' CHECK (unit IN ('L','GAL')),
  UNIQUE (station_id, code)
);

CREATE TABLE tanks (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  station_id      uuid NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
  controller_id   int REFERENCES controllers(id) ON DELETE SET NULL,
  label           text NOT NULL,
  rm_tank_id      int,                      -- FDTanques.ID
  pts_tank_number int NOT NULL,
  pts_probe_number int,
  fuel_product_id uuid REFERENCES fuel_products(id) ON DELETE SET NULL,
  capacity_liters numeric(10,2),
  alarm_high      numeric(10,2),
  alarm_low       numeric(10,2),
  UNIQUE (station_id, pts_tank_number)
);

CREATE TABLE tank_readings (
  id          bigserial PRIMARY KEY,
  tank_id     uuid NOT NULL REFERENCES tanks(id) ON DELETE CASCADE,
  volume      numeric(10,2),
  height      numeric(10,2),
  temperature numeric(6,2),
  water       numeric(10,2),
  read_at     timestamptz NOT NULL DEFAULT now(),
  source      text NOT NULL DEFAULT 'pts2link'
);
CREATE INDEX tank_readings_tank_idx ON tank_readings (tank_id, read_at DESC);

CREATE TABLE pumps (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  station_id      uuid NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
  controller_id   int REFERENCES controllers(id) ON DELETE SET NULL,
  number          int NOT NULL,             -- número visible en pista
  rm_pump_id      int,                      -- FDPumps.ID
  pts_pump_number int NOT NULL,
  price_level     int NOT NULL DEFAULT 1,   -- FDPumps.PriceLevel / ServLevID
  qr_token        text UNIQUE,              -- QR pegado al surtidor
  status          text NOT NULL DEFAULT 'unknown'
                  CHECK (status IN ('unknown','offline','idle','authorized','filling','end_of_transaction','blocked')),
  status_at       timestamptz,
  UNIQUE (station_id, number)
);

CREATE TABLE hoses (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pump_id          uuid NOT NULL REFERENCES pumps(id) ON DELETE CASCADE,
  position         int NOT NULL,            -- FDHoses.Posicion
  rm_hose_id       int,                     -- FDHoses.ID
  pts_nozzle_number int NOT NULL,
  fuel_product_id  uuid NOT NULL REFERENCES fuel_products(id) ON DELETE RESTRICT,
  UNIQUE (pump_id, position)
);

-- Precio operativo: se espeja desde FDPrecios (RM es la fuente autorizada)
CREATE TABLE fuel_prices (
  id              bigserial PRIMARY KEY,
  fuel_product_id uuid NOT NULL REFERENCES fuel_products(id) ON DELETE CASCADE,
  price_level     int NOT NULL DEFAULT 1,
  price           numeric(8,4) NOT NULL,
  tier2           numeric(8,4),
  effective_from  timestamptz NOT NULL DEFAULT now(),
  source          text NOT NULL DEFAULT 'rm_api'
);
CREATE INDEX fuel_prices_current_idx
  ON fuel_prices (fuel_product_id, price_level, effective_from DESC);

-- ── Catálogo del minimarket (espejo de solo lectura del POS) ─────────

CREATE TABLE products (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  station_id   uuid NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
  item_code    text NOT NULL,               -- ItemCode / Referencia en RM
  barcode      text,
  name         text NOT NULL,
  detail       text,
  department   text,
  category     text,
  price        numeric(10,2) NOT NULL,
  on_hand      numeric(10,2),
  aisle        text,                        -- ubicación para el picking
  active       boolean NOT NULL DEFAULT true,
  synced_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (station_id, item_code)
);
CREATE INDEX products_station_active_idx ON products (station_id, active);

-- ── Personal ─────────────────────────────────────────────────────────

CREATE TABLE employees (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  station_id    uuid NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
  badge         text NOT NULL UNIQUE,       -- EMP-0142
  full_name     text NOT NULL,
  role          text NOT NULL DEFAULT 'attendant'
                CHECK (role IN ('attendant','cashier','supervisor','manager')),
  pin_hash      text,
  rm_user_id    int,                        -- UserID que exige la RM API
  active        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE shifts (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  station_id  uuid NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  opened_at   timestamptz NOT NULL DEFAULT now(),
  closed_at   timestamptz
);

-- ── Ciclo de vida de la orden ────────────────────────────────────────

CREATE TABLE orders (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code                  text NOT NULL UNIQUE,      -- OC-2841
  edge_transaction_uuid uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  station_id            uuid NOT NULL REFERENCES stations(id),
  customer_id           uuid NOT NULL REFERENCES customers(id),
  vehicle_id            uuid REFERENCES vehicles(id),
  pump_id               uuid REFERENCES pumps(id),
  status                text NOT NULL DEFAULT 'draft' CHECK (status IN
                        ('draft','authorized','arrived','dispensing','dispensed','settled','cancelled','failed')),
  fuel_product_id       uuid REFERENCES fuel_products(id),
  price_per_unit        numeric(8,4),              -- congelado al autorizar
  cap_amount            numeric(10,2) NOT NULL DEFAULT 0,   -- techo de combustible
  items_amount          numeric(10,2) NOT NULL DEFAULT 0,   -- minimarket
  authorized_amount     numeric(10,2) NOT NULL DEFAULT 0,   -- retención pedida
  dispensed_amount      numeric(10,2) NOT NULL DEFAULT 0,
  dispensed_volume      numeric(10,3) NOT NULL DEFAULT 0,
  final_amount          numeric(10,2),
  released_amount       numeric(10,2),
  rm_request_id         uuid,                      -- RequestId enviado a FuelPumpAuthorize
  rm_invoice_number     text,                      -- factura creada en RM al liquidar
  pts_transaction_id    int,                       -- transacción reportada por el PTS-2
  created_at            timestamptz NOT NULL DEFAULT now(),
  authorized_at         timestamptz,
  arrived_at            timestamptz,
  dispensing_at         timestamptz,
  completed_at          timestamptz,
  cancelled_reason      text
);
CREATE INDEX orders_station_status_idx ON orders (station_id, status, created_at DESC);
CREATE INDEX orders_customer_idx ON orders (customer_id, created_at DESC);

CREATE TABLE order_items (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id    uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id  uuid REFERENCES products(id),
  item_code   text NOT NULL,
  name        text NOT NULL,
  qty         numeric(10,2) NOT NULL CHECK (qty > 0),
  unit_price  numeric(10,2) NOT NULL,
  line_total  numeric(10,2) NOT NULL,
  picked_at   timestamptz,
  substituted boolean NOT NULL DEFAULT false,
  delivered_at timestamptz
);
CREATE INDEX order_items_order_idx ON order_items (order_id);

-- Bitácora inmutable: cada transición y cada respuesta de RM / PTS
CREATE TABLE order_events (
  id         bigserial PRIMARY KEY,
  order_id   uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  type       text NOT NULL,      -- created | authorized | hold_placed | arrived | pump_authorized …
  actor      text NOT NULL DEFAULT 'system',  -- customer:<id> | employee:<id> | system | pts | rm
  payload    jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX order_events_order_idx ON order_events (order_id, id);

-- ── Pagos ────────────────────────────────────────────────────────────

CREATE TABLE payment_methods (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id  uuid NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  brand        text,
  last4        char(4),
  exp_month    int,
  exp_year     int,
  token        text NOT NULL,       -- token del procesador; nunca el PAN
  is_default   boolean NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE payment_holds (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id          uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  payment_method_id uuid REFERENCES payment_methods(id),
  amount            numeric(10,2) NOT NULL,
  status            text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','held','captured','released','expired','failed')),
  processor         text NOT NULL DEFAULT 'mock',
  processor_ref     text,
  authorized_at     timestamptz,
  expires_at        timestamptz,
  captured_amount   numeric(10,2),
  captured_at       timestamptz,
  released_at       timestamptz,
  failure_reason    text
);
CREATE INDEX payment_holds_status_idx ON payment_holds (status, expires_at);

-- ── Cumplimiento (app del empleado) ──────────────────────────────────

CREATE TABLE tasks (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id    uuid NOT NULL UNIQUE REFERENCES orders(id) ON DELETE CASCADE,
  station_id  uuid NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
  employee_id uuid REFERENCES employees(id),
  status      text NOT NULL DEFAULT 'incoming' CHECK (status IN
              ('incoming','accepted','picking','waiting','delivering','closed','escalated')),
  priority    boolean NOT NULL DEFAULT false,
  identity_ok boolean,
  accepted_at timestamptz,
  closed_at   timestamptz,
  note        text
);
CREATE INDEX tasks_station_status_idx ON tasks (station_id, status);

-- ── Integración: cola de salida hacia Retail Manager ─────────────────

CREATE TABLE rm_outbox (
  id           bigserial PRIMARY KEY,
  order_id     uuid REFERENCES orders(id) ON DELETE CASCADE,
  endpoint     text NOT NULL,        -- ImportExternalInvoice | FuelSetPrice | …
  payload      jsonb NOT NULL,
  status       text NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending','sent','failed','dead')),
  attempts     int NOT NULL DEFAULT 0,
  last_error   text,
  next_try_at  timestamptz NOT NULL DEFAULT now(),
  sent_at      timestamptz,
  response     jsonb,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX rm_outbox_pending_idx ON rm_outbox (status, next_try_at);

-- Comandos enviados al controlador (idempotencia por request_id)
CREATE TABLE pts_commands (
  id            bigserial PRIMARY KEY,
  order_id      uuid REFERENCES orders(id) ON DELETE CASCADE,
  controller_id int REFERENCES controllers(id),
  request_id    uuid NOT NULL UNIQUE,
  command       text NOT NULL,        -- FuelPumpAuthorize | PumpStop | PumpGetStatus
  params        jsonb NOT NULL DEFAULT '{}'::jsonb,
  status        text NOT NULL DEFAULT 'queued'
                CHECK (status IN ('queued','sent','acked','failed')),
  response      jsonb,
  error         text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  acked_at      timestamptz
);

CREATE TABLE audit_log (
  id         bigserial PRIMARY KEY,
  actor      text NOT NULL,
  action     text NOT NULL,
  entity     text,
  entity_id  text,
  result     text NOT NULL DEFAULT 'ok',
  ip         text,
  detail     jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_log_created_idx ON audit_log (created_at DESC);

-- ── Vistas de apoyo ──────────────────────────────────────────────────

CREATE VIEW v_current_fuel_prices AS
SELECT fp.id AS fuel_product_id,
       fp.station_id,
       fp.code,
       fp.display_name,
       fp.pts_grade_id,
       p.price_level,
       p.price,
       p.effective_from
FROM fuel_products fp
JOIN LATERAL (
  SELECT price, price_level, effective_from
  FROM fuel_prices
  WHERE fuel_product_id = fp.id
  ORDER BY effective_from DESC
  LIMIT 1
) p ON true;

CREATE VIEW v_open_orders AS
SELECT o.*, t.status AS task_status, t.employee_id
FROM orders o
LEFT JOIN tasks t ON t.order_id = o.id
WHERE o.status IN ('authorized','arrived','dispensing','dispensed');
