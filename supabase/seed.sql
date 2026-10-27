-- Demo data for development. Ward shapes, emails and sites are made up.
-- Real ward boundaries come from the municipal open-data portals; real sites
-- come from pipeline/. City ids match api/ (indore, bhopal) and
-- pipeline/configs/cities.yaml (the Pune and Delhi uuids).

-- A square of about area_m2 around a point, built in UTM 43N metres.
create or replace function pg_temp.demo_square(lon double precision, lat double precision, area_m2 double precision)
returns geometry language sql immutable as $$
  select ST_Transform(ST_Expand(ST_Transform(ST_SetSRID(ST_Point(lon, lat), 4326), 32643), sqrt(area_m2) / 2), 4326);
$$;

create or replace function pg_temp.bbox(w double precision, s double precision, e double precision, n double precision)
returns geometry language sql immutable as $$
  select ST_MakeEnvelope(w, s, e, n, 4326);
$$;

insert into public.cities (id, name, state, bbox, area_km2, is_pilot) values
  ('indore', 'Indore', 'Madhya Pradesh', pg_temp.bbox(75.72, 22.60, 75.98, 22.82), 530, true),
  ('bhopal', 'Bhopal', 'Madhya Pradesh', pg_temp.bbox(77.28, 23.15, 77.52, 23.33), 463, true),
  ('11111111-1111-1111-1111-111111111111', 'Pune', 'Maharashtra', pg_temp.bbox(73.74, 18.42, 73.98, 18.64), 331, true),
  ('22222222-2222-2222-2222-222222222222', 'Delhi', 'Delhi', pg_temp.bbox(76.84, 28.40, 77.35, 28.88), 1484, true)
on conflict (id) do nothing;

insert into public.wards (id, city_id, ward_no, name, officer_name, officer_email, geom) values
  ('w-ind-12', 'indore', 12, 'Rau', 'Ward 12 Officer', 'ward12.indore@example.com', pg_temp.bbox(75.75, 22.60, 75.85, 22.70)),
  ('w-ind-5', 'indore', 5, 'Sudama Nagar', 'Ward 5 Officer', 'ward5.indore@example.com', pg_temp.bbox(75.80, 22.67, 75.90, 22.77)),
  ('w-bho-8', 'bhopal', 8, 'Kolar', 'Ward 8 Officer', 'ward8.bhopal@example.com', pg_temp.bbox(77.35, 23.15, 77.45, 23.25)),
  ('w-pune-1', '11111111-1111-1111-1111-111111111111', 1, 'Demo Ward', 'Demo Officer', 'ward1.pune@example.com', pg_temp.bbox(73.84, 18.50, 73.88, 18.54))
on conflict (id) do nothing;

-- ward_id, centroid and area_m2 are filled by the sites_derive trigger.
insert into public.sites (id, city_id, geom, first_seen, last_seen, near_water, status, fire_risk, confidence, growth) values
  ('site-1', 'indore', pg_temp.demo_square(75.8000, 22.6500, 3200), '2026-04-14', '2026-10-18', true, 'active', 72, 0.86, 'grew ~1800 m2 since first seen'),
  ('site-2', 'indore', pg_temp.demo_square(75.8500, 22.7200, 1100), '2026-09-30', '2026-10-17', false, 'active', 40, 0.81, 'stable'),
  ('site-3', 'bhopal', pg_temp.demo_square(77.4000, 23.2000, 4700), '2026-07-02', '2026-10-19', true, 'active', 61, 0.90, 'grew ~1500 m2 since first seen'),
  ('site-4', 'indore', pg_temp.demo_square(75.8300, 22.6900, 1500), '2026-10-12', '2026-10-12', false, 'active', 10, 0.45, 'new, low confidence'),
  ('site-5', '11111111-1111-1111-1111-111111111111', pg_temp.demo_square(73.8606, 18.5205, 2500), '2026-05-10', '2026-10-05', false, 'active', 35, 0.88, 'grew ~1300 m2 since first seen')
on conflict (id) do nothing;

insert into public.scenes (id, city_id, stac_item_id, acquired_at, cloud_cover, status) values
  ('sc-ind-0414', 'indore', 'DEMO_S2_INDORE_20260414', '2026-04-14 05:30+00', 3.1, 'processed'),
  ('sc-ind-0716', 'indore', 'DEMO_S2_INDORE_20260716', '2026-07-16 05:30+00', 12.4, 'processed'),
  ('sc-ind-1018', 'indore', 'DEMO_S2_INDORE_20261018', '2026-10-18 05:30+00', 1.8, 'processed'),
  ('sc-bho-0702', 'bhopal', 'DEMO_S2_BHOPAL_20260702', '2026-07-02 05:30+00', 8.0, 'processed'),
  ('sc-bho-1019', 'bhopal', 'DEMO_S2_BHOPAL_20261019', '2026-10-19 05:30+00', 2.2, 'processed'),
  ('sc-pune-0510', '11111111-1111-1111-1111-111111111111', 'DEMO_S2_PUNE_20260510', '2026-05-10 05:30+00', 4.0, 'processed'),
  ('sc-pune-1005', '11111111-1111-1111-1111-111111111111', 'DEMO_S2_PUNE_20261005', '2026-10-05 05:30+00', 6.5, 'processed')
on conflict (id) do nothing;

-- Detection history: each site growing over six months (for the time slider).
-- detected_on is filled from the scene date by the detections_derive trigger.
insert into public.detections (id, site_id, scene_id, geom, confidence) values
  ('det-1a', 'site-1', 'sc-ind-0414', pg_temp.demo_square(75.8000, 22.6500, 1400), 0.71),
  ('det-1b', 'site-1', 'sc-ind-0716', pg_temp.demo_square(75.8000, 22.6500, 2300), 0.80),
  ('det-1c', 'site-1', 'sc-ind-1018', pg_temp.demo_square(75.8000, 22.6500, 3200), 0.86),
  ('det-2a', 'site-2', 'sc-ind-0716', pg_temp.demo_square(75.8500, 22.7200, 1100), 0.78),
  ('det-2b', 'site-2', 'sc-ind-1018', pg_temp.demo_square(75.8500, 22.7200, 1100), 0.81),
  ('det-3a', 'site-3', 'sc-bho-0702', pg_temp.demo_square(77.4000, 23.2000, 3200), 0.84),
  ('det-3b', 'site-3', 'sc-bho-1019', pg_temp.demo_square(77.4000, 23.2000, 4700), 0.90),
  ('det-4a', 'site-4', 'sc-ind-1018', pg_temp.demo_square(75.8300, 22.6900, 1500), 0.45),
  ('det-5a', 'site-5', 'sc-pune-0510', pg_temp.demo_square(73.8606, 18.5205, 1200), 0.74),
  ('det-5b', 'site-5', 'sc-pune-1005', pg_temp.demo_square(73.8606, 18.5205, 2500), 0.88)
on conflict (id) do nothing;

insert into public.fire_events (id, site_id, detected_at, lat, lon, frp, confidence, source) values
  ('fe-1', 'site-1', '2026-10-16 06:00+00', 22.6502, 75.8003, 12.5, 'n', 'VIIRS'),
  ('fe-2', 'site-3', '2026-10-11 07:40+00', 23.2003, 77.4001, 8.1, 'h', 'VIIRS'),
  ('fe-3', null, '2026-10-20 06:10+00', 22.7600, 75.9300, 4.0, 'l', 'VIIRS')
on conflict (id) do nothing;
update public.fire_events set city_id = 'indore' where id = 'fe-3';

-- site-2 is on a government list; the others are not.
insert into public.official_sites (id, city_id, name, geom, source) values
  ('off-ind-1', 'indore', 'Known dumping point (demo record)', ST_SetSRID(ST_Point(75.8501, 22.7201), 4326), 'DEMO municipal list')
on conflict (id) do nothing;

insert into public.city_scores (city_id, period, score, active_sites, burn_events, median_days_to_clear, pct_verified_cleared, parts, weights) values
  ('indore', '2026-09', 71, 3, 1, 30, 0, '{"active": 0.998, "burn": 0.95, "clear_time": 0.5, "verified": 0}', '{"active": 40, "burn": 25, "clear_time": 20, "verified": 15}'),
  ('bhopal', '2026-09', 69, 1, 1, 30, 0, '{"active": 1.0, "burn": 0.95, "clear_time": 0.5, "verified": 0}', '{"active": 40, "burn": 25, "clear_time": 20, "verified": 15}'),
  ('11111111-1111-1111-1111-111111111111', '2026-09', 74, 1, 0, 30, 0, '{"active": 0.999, "burn": 1.0, "clear_time": 0.5, "verified": 0}', '{"active": 40, "burn": 25, "clear_time": 20, "verified": 15}'),
  ('22222222-2222-2222-2222-222222222222', '2026-09', 75, 0, 0, 30, 0, '{"active": 1.0, "burn": 1.0, "clear_time": 0.5, "verified": 0}', '{"active": 40, "burn": 25, "clear_time": 20, "verified": 15}')
on conflict (city_id, period) do nothing;

-- Earlier months, so the scores screen has a trend to show (A-20).
insert into public.city_scores (city_id, period, score, active_sites, burn_events, median_days_to_clear, pct_verified_cleared) values
  ('indore', '2026-05', 63, 4, 3, 45, 0), ('indore', '2026-06', 65, 4, 2, 40, 0),
  ('indore', '2026-07', 66, 3, 2, 38, 0), ('indore', '2026-08', 69, 3, 1, 34, 0),
  ('bhopal', '2026-05', 61, 2, 3, 50, 0), ('bhopal', '2026-06', 62, 2, 3, 48, 0),
  ('bhopal', '2026-07', 64, 2, 2, 44, 0), ('bhopal', '2026-08', 66, 1, 2, 40, 0),
  ('11111111-1111-1111-1111-111111111111', '2026-05', 70, 1, 1, 35, 0), ('11111111-1111-1111-1111-111111111111', '2026-06', 71, 1, 1, 33, 0),
  ('11111111-1111-1111-1111-111111111111', '2026-07', 72, 1, 0, 32, 0), ('11111111-1111-1111-1111-111111111111', '2026-08', 73, 1, 0, 31, 0),
  ('22222222-2222-2222-2222-222222222222', '2026-05', 74, 0, 0, 30, 0), ('22222222-2222-2222-2222-222222222222', '2026-06', 74, 0, 0, 30, 0),
  ('22222222-2222-2222-2222-222222222222', '2026-07', 75, 0, 0, 30, 0), ('22222222-2222-2222-2222-222222222222', '2026-08', 75, 0, 0, 30, 0)
on conflict (city_id, period) do nothing;

-- Areas for the home page search (centres are approximate). Kothrud and Aundh
-- are outside the demo ward, so they show how an uncovered ward reads.
insert into public.localities (id, city_id, name, name_hi, pincode, centroid) values
  ('loc-pune-shivajinagar', '11111111-1111-1111-1111-111111111111', 'Shivajinagar', 'शिवाजीनगर', '411005', ST_SetSRID(ST_Point(73.8475, 18.5308), 4326)),
  ('loc-pune-deccan', '11111111-1111-1111-1111-111111111111', 'Deccan Gymkhana', 'डेक्कन जिमखाना', '411004', ST_SetSRID(ST_Point(73.8411, 18.5167), 4326)),
  ('loc-pune-kothrud', '11111111-1111-1111-1111-111111111111', 'Kothrud', 'कोथरुड', '411038', ST_SetSRID(ST_Point(73.8077, 18.5074), 4326)),
  ('loc-pune-aundh', '11111111-1111-1111-1111-111111111111', 'Aundh', 'औंध', '411007', ST_SetSRID(ST_Point(73.8070, 18.5590), 4326)),
  ('loc-ind-rau', 'indore', 'Rau', 'राऊ', '453331', ST_SetSRID(ST_Point(75.8110, 22.6360), 4326)),
  ('loc-ind-sudama', 'indore', 'Sudama Nagar', 'सुदामा नगर', '452009', ST_SetSRID(ST_Point(75.8300, 22.6900), 4326)),
  ('loc-bho-kolar', 'bhopal', 'Kolar Road', 'कोलार रोड', '462042', ST_SetSRID(ST_Point(77.4100, 23.1800), 4326)),
  ('loc-del-okhla', '22222222-2222-2222-2222-222222222222', 'Okhla', 'ओखला', '110020', ST_SetSRID(ST_Point(77.2700, 28.5300), 4326))
on conflict (id) do nothing;

-- One made-up PWD road through the Pune demo ward, so debris routing can be tried.
insert into public.pwd_roads (id, city_id, name, geom) values
  ('pwd-pune-demo', '11111111-1111-1111-1111-111111111111', 'PWD road (demo)',
   ST_SetSRID(ST_MakeLine(ST_Point(73.8450, 18.5150), ST_Point(73.8750, 18.5150)), 4326))
on conflict (id) do nothing;
