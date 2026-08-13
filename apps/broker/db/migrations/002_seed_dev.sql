-- Semilla de desarrollo: refleja el PTS-2 real de 192.168.100.251
-- (4 bombas en el puerto 1, mangueras 1-3 → grados 1 Petrol, 2 Diesel, 3 LPG,
--  tanques 1-3 con sondas 1-3). Idempotente.

INSERT INTO stations (id, code, name, address, town, lat, lng, rm_api_base, pts2link_base)
VALUES ('11111111-1111-1111-1111-111111111111', 'ST-101', 'Octano Isla Verde',
        'Ave. Isla Verde 5900', 'Carolina', 18.4408, -66.0084,
        'http://localhost:8180', 'http://localhost:9080')
ON CONFLICT (code) DO NOTHING;

INSERT INTO controllers (id, station_id, name, host, port, protocol, auth_mode,
                         pts_unique_id, tls_fingerprint, firmware)
VALUES (1, '11111111-1111-1111-1111-111111111111', 'PTS-2 Principal',
        '192.168.100.251', 443, 'https', 'digest',
        '003C00223233511330313337',
        '0023856F525A8776834F0E6A892632EC1F9F0E7313C5E18749570123A6152E76',
        '2026.03.21 13:34:21')
ON CONFLICT (id) DO NOTHING;

INSERT INTO fuel_products (station_id, code, display_name, pts_grade_id, rm_product_id)
VALUES
 ('11111111-1111-1111-1111-111111111111', 'r87', 'Regular 87', 1, NULL),
 ('11111111-1111-1111-1111-111111111111', 'dsl', 'Diésel',     2, NULL),
 ('11111111-1111-1111-1111-111111111111', 'lpg', 'LPG',        3, NULL)
ON CONFLICT (station_id, code) DO NOTHING;

INSERT INTO tanks (station_id, controller_id, label, pts_tank_number, pts_probe_number,
                   fuel_product_id, capacity_liters, alarm_high, alarm_low)
SELECT '11111111-1111-1111-1111-111111111111', 1, t.label, t.num, t.probe,
       fp.id, t.cap, t.hi, t.lo
FROM (VALUES
        ('Tanque 1', 1, 1, 'r87', 3750, 3500, 300),
        ('Tanque 2', 2, 2, 'dsl', 3250, 3150, 300),
        ('Tanque 3', 3, 3, 'lpg', 2750, 2500, 200)
     ) AS t(label, num, probe, code, cap, hi, lo)
JOIN fuel_products fp
  ON fp.station_id = '11111111-1111-1111-1111-111111111111' AND fp.code = t.code
ON CONFLICT (station_id, pts_tank_number) DO NOTHING;

INSERT INTO pumps (station_id, controller_id, number, pts_pump_number, price_level, qr_token)
SELECT '11111111-1111-1111-1111-111111111111', 1, n, n, 1, 'QR-ST101-P' || n
FROM generate_series(1, 4) AS n
ON CONFLICT (station_id, number) DO NOTHING;

-- Mangueras: cada bomba tiene 3 (Petrol, Diesel, LPG), igual que el controlador real
INSERT INTO hoses (pump_id, position, pts_nozzle_number, fuel_product_id)
SELECT p.id, h.pos, h.pos, fp.id
FROM pumps p
CROSS JOIN (VALUES (1, 'r87'), (2, 'dsl'), (3, 'lpg')) AS h(pos, code)
JOIN fuel_products fp
  ON fp.station_id = p.station_id AND fp.code = h.code
WHERE p.station_id = '11111111-1111-1111-1111-111111111111'
ON CONFLICT (pump_id, position) DO NOTHING;

-- Precios iniciales (se sobreescriben con FuelPrices de la RM API)
INSERT INTO fuel_prices (fuel_product_id, price_level, price, source)
SELECT fp.id, 1, v.price, 'seed'
FROM (VALUES ('r87', 0.87), ('dsl', 0.94), ('lpg', 1.45)) AS v(code, price)
JOIN fuel_products fp
  ON fp.station_id = '11111111-1111-1111-1111-111111111111' AND fp.code = v.code
WHERE NOT EXISTS (SELECT 1 FROM fuel_prices f WHERE f.fuel_product_id = fp.id);

INSERT INTO products (station_id, item_code, name, detail, category, price, aisle, on_hand)
VALUES
 ('11111111-1111-1111-1111-111111111111','MM-CAFE-16','Café con leche 16 oz','Recién colado','Café',2.75,'Barra',99),
 ('11111111-1111-1111-1111-111111111111','MM-AGUA-1L','Agua 1 L','Fría','Bebidas',1.50,'N1',60),
 ('11111111-1111-1111-1111-111111111111','MM-PAPITAS','Papitas clásicas','Bolsa 2.5 oz','Snacks',1.75,'P3',40),
 ('11111111-1111-1111-1111-111111111111','MM-SANDW','Sándwich de jamón','Pan sobao','Snacks',4.50,'Barra',12),
 ('11111111-1111-1111-1111-111111111111','MM-HIELO','Hielo 5 lb','Bolsa','Esenciales',3.50,'Congelador',25)
ON CONFLICT (station_id, item_code) DO NOTHING;

INSERT INTO employees (station_id, badge, full_name, role, rm_user_id)
VALUES ('11111111-1111-1111-1111-111111111111', 'EMP-0142', 'Luis Martínez', 'attendant', 2)
ON CONFLICT (badge) DO NOTHING;

INSERT INTO customers (id, phone, full_name, email, photo_verified_at)
VALUES ('22222222-2222-2222-2222-222222222222', '+17875550142', 'Carlos Omar',
        'carlos@retailmanagerpr.com', now())
ON CONFLICT (phone) DO NOTHING;

INSERT INTO wallets (customer_id, balance)
SELECT '22222222-2222-2222-2222-222222222222', 42.60
ON CONFLICT (customer_id) DO NOTHING;

INSERT INTO vehicles (customer_id, plate, make_model, color, tank_liters, is_default)
VALUES ('22222222-2222-2222-2222-222222222222', 'HJK-482', 'Toyota Corolla 2021',
        'Gris plata', 50, true)
ON CONFLICT (customer_id, plate) DO NOTHING;

INSERT INTO payment_methods (customer_id, brand, last4, exp_month, exp_year, token, is_default)
VALUES ('22222222-2222-2222-2222-222222222222', 'VISA', '4417', 12, 2029, 'tok_dev_4417', true)
ON CONFLICT DO NOTHING;
