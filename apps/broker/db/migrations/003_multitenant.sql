-- ════════════════════════════════════════════════════════════════════
-- Multi-tenant: un broker, muchos clientes (operadores), muchas
-- estaciones, y CADA estación con sus propios endpoints de Retail
-- Manager / PTS2Link / pagos. Nada de URLs en el .env salvo el
-- arranque; la configuración vive en la base y se administra por API.
-- ════════════════════════════════════════════════════════════════════

-- ── Cliente / operador (dueño de una o varias estaciones) ────────────
CREATE TABLE tenants (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code         text NOT NULL UNIQUE,          -- 'RM-PR', 'GASOMAX'
  name         text NOT NULL,
  contact_name text,
  contact_email text,
  status       text NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','trial')),
  settings     jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at   timestamptz NOT NULL DEFAULT now()
);

INSERT INTO tenants (id, code, name)
VALUES ('33333333-3333-3333-3333-333333333333', 'RM-PR', 'Retail Manager Puerto Rico')
ON CONFLICT (code) DO NOTHING;

ALTER TABLE stations
  ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS currency char(3) NOT NULL DEFAULT 'USD',
  ADD COLUMN IF NOT EXISTS volume_unit text NOT NULL DEFAULT 'L' CHECK (volume_unit IN ('L','GAL')),
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active'
      CHECK (status IN ('active','paused','onboarding','disabled'));

UPDATE stations SET tenant_id = '33333333-3333-3333-3333-333333333333' WHERE tenant_id IS NULL;
ALTER TABLE stations ALTER COLUMN tenant_id SET NOT NULL;
CREATE INDEX IF NOT EXISTS stations_tenant_idx ON stations (tenant_id);

-- rm_api_base / pts2link_base quedan como referencia histórica; la fuente
-- autorizada ahora es la tabla integrations.
COMMENT ON COLUMN stations.rm_api_base IS 'Obsoleto: usar integrations(kind=rm_api).base_url';
COMMENT ON COLUMN stations.pts2link_base IS 'Obsoleto: usar integrations(kind=pts2link).base_url';

-- ── Endpoints por estación ───────────────────────────────────────────
-- Una fila por enlace. Los secretos se guardan cifrados (AES-256-GCM con
-- MASTER_KEY); la API nunca los devuelve en claro.
CREATE TABLE integrations (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  station_id     uuid REFERENCES stations(id) ON DELETE CASCADE,   -- NULL = default del tenant
  kind           text NOT NULL CHECK (kind IN ('rm_api','pts2link','pts_direct','payments','push')),
  label          text NOT NULL,
  base_url       text NOT NULL,
  auth_type      text NOT NULL DEFAULT 'none'
                 CHECK (auth_type IN ('none','basic','digest','bearer','apikey','query')),
  username       text,
  secret_enc     text,          -- password / token / api key, cifrado
  extra_enc      text,          -- credenciales adicionales, cifradas (JSON)
  timeout_ms     int NOT NULL DEFAULT 8000,
  verify_tls     boolean NOT NULL DEFAULT true,
  tls_fingerprint text,         -- pinning para certificados autofirmados (PTS-2)
  settings       jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- settings usados hoy:
  --  rm_api:   { "userId": "2", "channel": 1, "fuelMop": "CREDIT",
  --              "fuelProductCode": "FUEL", "pathPrefix": "cse.api.v1" }
  --  pts2link: { "paths": { "pumps": "/api/pumps", "tanks": "/api/tanks",
  --              "pumpStatus": "/api/pumps/{pump}/status",
  --              "health": "/api/health", "controllers": "/api/controllers",
  --              "mappings": "/api/mappings" }, "wsUrl": "ws://host/ws" }
  enabled        boolean NOT NULL DEFAULT true,
  is_primary     boolean NOT NULL DEFAULT true,
  last_check_at  timestamptz,
  last_check_ok  boolean,
  last_check_note text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX integrations_primary_idx
  ON integrations (station_id, kind) WHERE is_primary AND station_id IS NOT NULL;
CREATE INDEX integrations_tenant_kind_idx ON integrations (tenant_id, kind, enabled);

-- ── Reglas de negocio por estación (impuestos, techos, retención) ────
CREATE TABLE station_rules (
  station_id        uuid PRIMARY KEY REFERENCES stations(id) ON DELETE CASCADE,
  hold_ttl_minutes  int NOT NULL DEFAULT 60,
  max_auth_amount   numeric(10,2) NOT NULL DEFAULT 200,
  min_auth_amount   numeric(10,2) NOT NULL DEFAULT 5,
  city_tax_rate     numeric(6,4) NOT NULL DEFAULT 0,      -- IVU municipal (PR: 0.01)
  state_tax_rate    numeric(6,4) NOT NULL DEFAULT 0,      -- IVU estatal (PR: 0.105)
  fuel_taxable      boolean NOT NULL DEFAULT false,
  items_taxable     boolean NOT NULL DEFAULT true,
  invoice_series    text NOT NULL DEFAULT 'M',            -- ImportExternalInvoice.Factura
  default_rm_client text NOT NULL DEFAULT '0000',
  updated_at        timestamptz NOT NULL DEFAULT now()
);

INSERT INTO station_rules (station_id)
SELECT id FROM stations
ON CONFLICT (station_id) DO NOTHING;

-- ── Usuarios de consola (panel admin multi-estación) ─────────────────
CREATE TABLE console_users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid REFERENCES tenants(id) ON DELETE CASCADE,  -- NULL = superadmin
  email         text NOT NULL UNIQUE,
  full_name     text NOT NULL,
  role          text NOT NULL DEFAULT 'operator'
                CHECK (role IN ('superadmin','tenant_admin','operator','viewer')),
  password_hash text,
  active        boolean NOT NULL DEFAULT true,
  last_login_at timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- ── Los clientes de la app se atan al tenant ─────────────────────────
ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE RESTRICT;
UPDATE customers SET tenant_id = '33333333-3333-3333-3333-333333333333' WHERE tenant_id IS NULL;
CREATE INDEX IF NOT EXISTS customers_tenant_idx ON customers (tenant_id);

ALTER TABLE employees
  ADD COLUMN IF NOT EXISTS rm_user_pass_enc text;

-- ── Bitácora de cambios de configuración ─────────────────────────────
CREATE TABLE integration_events (
  id             bigserial PRIMARY KEY,
  integration_id uuid REFERENCES integrations(id) ON DELETE CASCADE,
  actor          text NOT NULL,
  action         text NOT NULL,   -- created | updated | tested | disabled
  detail         jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at     timestamptz NOT NULL DEFAULT now()
);

-- Vista de resolución: qué enlace usa cada estación para cada tipo.
CREATE VIEW v_station_integrations AS
SELECT s.id AS station_id,
       s.tenant_id,
       s.code AS station_code,
       i.kind,
       i.id AS integration_id,
       i.label,
       i.base_url,
       i.auth_type,
       i.username,
       i.timeout_ms,
       i.verify_tls,
       i.tls_fingerprint,
       i.settings,
       i.enabled,
       i.last_check_ok,
       i.last_check_at
FROM stations s
JOIN integrations i
  ON i.enabled
 AND (i.station_id = s.id OR (i.station_id IS NULL AND i.tenant_id = s.tenant_id));
