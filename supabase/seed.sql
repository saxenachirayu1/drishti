-- Demo data for development. Everything here is made up and marked DEMO.
-- Real city/ward boundaries and detections replace it once pipeline/ runs.

insert into public.cities (id, name, state, slug, is_pilot, center, boundary) values
  ('00000000-0000-0000-0000-000000000001', 'Pune', 'Maharashtra', 'pune', true,
   ST_SetSRID(ST_MakePoint(73.8567, 18.5204), 4326),
   ST_GeomFromText('POLYGON((73.75 18.43, 73.98 18.43, 73.98 18.63, 73.75 18.63, 73.75 18.43))', 4326)),
  ('00000000-0000-0000-0000-000000000002', 'Delhi', 'Delhi', 'delhi', true,
   ST_SetSRID(ST_MakePoint(77.2090, 28.6139), 4326),
   ST_GeomFromText('POLYGON((76.84 28.40, 77.35 28.40, 77.35 28.88, 76.84 28.88, 76.84 28.40))', 4326))
on conflict (id) do nothing;

insert into public.wards (id, city_id, ward_number, name, officer_name, officer_email, boundary) values
  ('00000000-0000-0000-0001-000000000001', '00000000-0000-0000-0000-000000000001',
   'DEMO-1', 'DEMO Ward 1', 'Demo Officer', 'demo-ward-officer@example.com',
   ST_GeomFromText('POLYGON((73.84 18.50, 73.88 18.50, 73.88 18.54, 73.84 18.54, 73.84 18.50))', 4326))
on conflict (id) do nothing;

-- ward_id, centroid and area_m2 are filled by the sites_derive trigger.
insert into public.sites (id, city_id, name, site_type, status, confidence, near_water,
                          first_seen_at, last_seen_at, geom) values
  ('00000000-0000-0000-0002-000000000001', '00000000-0000-0000-0000-000000000001',
   'DEMO dumpsite', 'dumpsite', 'detected', 0.91, false, '2026-04-10', '2026-10-05',
   ST_GeomFromText('POLYGON((73.8600 18.5200, 73.8612 18.5200, 73.8612 18.5211, 73.8600 18.5211, 73.8600 18.5200))', 4326))
on conflict (id) do nothing;

-- Three sightings of the same site, growing over six months (for the time slider).
insert into public.detections (city_id, site_id, detected_on, confidence, model_version, geom) values
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0002-000000000001', '2026-04-10', 0.78, 'demo',
   ST_GeomFromText('POLYGON((73.8603 18.5203, 73.8607 18.5203, 73.8607 18.5207, 73.8603 18.5207, 73.8603 18.5203))', 4326)),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0002-000000000001', '2026-07-08', 0.86, 'demo',
   ST_GeomFromText('POLYGON((73.8601 18.5201, 73.8610 18.5201, 73.8610 18.5209, 73.8601 18.5209, 73.8601 18.5201))', 4326)),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0002-000000000001', '2026-10-05', 0.91, 'demo',
   ST_GeomFromText('POLYGON((73.8600 18.5200, 73.8612 18.5200, 73.8612 18.5211, 73.8600 18.5211, 73.8600 18.5200))', 4326));

insert into public.fire_events (city_id, site_id, source, firms_key, geom, acquired_at, frp, confidence) values
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0002-000000000001',
   'DEMO', 'demo-1', ST_SetSRID(ST_MakePoint(73.8606, 18.5205), 4326), '2026-10-01 14:20+05:30', 4.2, 'n')
on conflict (firms_key) do nothing;

insert into public.fire_risk_scores (site_id, score, temperature_c, humidity_pct, wind_kmh, days_since_rain) values
  ('00000000-0000-0000-0002-000000000001', 72, 34, 28, 14, 19);

insert into public.city_scores (city_id, period_start, period_end, score, active_sites, new_sites, cleared_sites, burning_events) values
  ('00000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-30', 64, 1, 1, 0, 1),
  ('00000000-0000-0000-0000-000000000002', '2026-09-01', '2026-09-30', 58, 0, 0, 0, 0)
on conflict (city_id, period_start, period_end) do nothing;
