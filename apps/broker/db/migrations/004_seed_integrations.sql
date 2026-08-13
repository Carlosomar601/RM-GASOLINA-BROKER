-- Semilla multi-tenant: registra los enlaces de la estación de prueba como
-- filas de `integrations` (lo que antes vivía en el .env).
-- Los secretos se guardan cifrados por la API; esta semilla deja
-- secret_enc en NULL y los llenas con:
--   PUT /v1/admin/integrations/:id  { "secret": "..." }

INSERT INTO integrations (tenant_id, station_id, kind, label, base_url, auth_type, username, settings)
SELECT s.tenant_id, s.id, 'rm_api', 'Retail Manager · POS-02\CSE', 'http://localhost:8180', 'query', '2',
       jsonb_build_object(
         'userId', '2',
         'channel', 1,
         'fuelMop', 'CREDIT',
         'fuelProductCode', 'FUEL',
         'pathPrefix', 'cse.api.v1'
       )
FROM stations s
WHERE s.code = 'ST-101'
  AND NOT EXISTS (
    SELECT 1 FROM integrations i WHERE i.station_id = s.id AND i.kind = 'rm_api'
  );

INSERT INTO integrations (tenant_id, station_id, kind, label, base_url, auth_type, settings)
SELECT s.tenant_id, s.id, 'pts2link', 'PTS2Link local', 'http://localhost:9080', 'none',
       jsonb_build_object(
         'wsUrl', 'ws://localhost:9080/ws',
         'paths', jsonb_build_object(
           'health', '/api/health',
           'controllers', '/api/controllers',
           'pumps', '/api/pumps',
           'pumpStatus', '/api/pumps/{pump}/status',
           'tanks', '/api/tanks',
           'mappings', '/api/mappings'
         )
       )
FROM stations s
WHERE s.code = 'ST-101'
  AND NOT EXISTS (
    SELECT 1 FROM integrations i WHERE i.station_id = s.id AND i.kind = 'pts2link'
  );

-- PTS-2 directo: solo diagnóstico, apagado por defecto, con huella fijada.
INSERT INTO integrations (tenant_id, station_id, kind, label, base_url, auth_type, username,
                          verify_tls, tls_fingerprint, enabled, settings)
SELECT s.tenant_id, s.id, 'pts_direct', 'PTS-2 Principal (jsonPTS)', 'https://192.168.100.251:443',
       'digest', 'admin', false,
       '0023856F525A8776834F0E6A892632EC1F9F0E7313C5E18749570123A6152E76', false,
       jsonb_build_object('uniqueId', '003C00223233511330313337', 'path', '/jsonPTS')
FROM stations s
WHERE s.code = 'ST-101'
  AND NOT EXISTS (
    SELECT 1 FROM integrations i WHERE i.station_id = s.id AND i.kind = 'pts_direct'
  );

-- Reglas de PR: IVU 10.5% estatal + 1% municipal sobre artículos; el
-- combustible no lleva IVU.
UPDATE station_rules sr
   SET state_tax_rate = 0.105, city_tax_rate = 0.010,
       fuel_taxable = false, items_taxable = true, updated_at = now()
 FROM stations s
WHERE s.id = sr.station_id AND s.code = 'ST-101';
