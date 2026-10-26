import 'package:latlong2/latlong.dart';

import 'parse.dart';

/// A row of `city_list`.
class City {
  const City({
    required this.id,
    required this.name,
    this.state,
    this.isPilot = false,
    this.areaKm2,
    this.lat,
    this.lng,
    this.west,
    this.south,
    this.east,
    this.north,
  });

  final String id;
  final String name;
  final String? state;
  final bool isPilot;
  final double? areaKm2;
  final double? lat;
  final double? lng;
  final double? west;
  final double? south;
  final double? east;
  final double? north;

  LatLng? get center => lat == null || lng == null ? null : LatLng(lat!, lng!);

  bool get hasBounds => west != null && south != null && east != null && north != null;

  factory City.fromMap(Map<String, dynamic> m) => City(
    id: m['id'] as String,
    name: m['name'] as String,
    state: m['state'] as String?,
    isPilot: m['is_pilot'] as bool? ?? false,
    areaKm2: asDouble(m['area_km2']),
    lat: asDouble(m['lat']),
    lng: asDouble(m['lng']),
    west: asDouble(m['west']),
    south: asDouble(m['south']),
    east: asDouble(m['east']),
    north: asDouble(m['north']),
  );
}

/// A row of `ward_map`.
class Ward {
  const Ward({
    required this.id,
    required this.cityId,
    this.wardNo,
    this.name,
    this.officerName,
    this.officerEmail,
    this.rings = const [],
  });

  final String id;
  final String cityId;
  final int? wardNo;
  final String? name;
  final String? officerName;
  final String? officerEmail;
  final List<List<LatLng>> rings;

  factory Ward.fromMap(Map<String, dynamic> m) => Ward(
    id: m['id'] as String,
    cityId: m['city_id'] as String,
    wardNo: asInt(m['ward_no']),
    name: m['name'] as String?,
    officerName: m['officer_name'] as String?,
    officerEmail: m['officer_email'] as String?,
    rings: outerRings(m['geojson']),
  );
}

/// A row of `city_leaderboard`: the latest score of one city.
class CityScore {
  const CityScore({
    required this.cityId,
    required this.name,
    required this.period,
    required this.score,
    required this.rank,
    this.state,
    this.activeSites = 0,
    this.burnEvents = 0,
    this.medianDaysToClear,
    this.pctVerifiedCleared,
    this.parts = const {},
  });

  final String cityId;
  final String name;
  final String? state;
  final String period;
  final int score;
  final int rank;
  final int activeSites;
  final int burnEvents;
  final double? medianDaysToClear;
  final double? pctVerifiedCleared;
  final Map<String, double> parts;

  factory CityScore.fromMap(Map<String, dynamic> m) => CityScore(
    cityId: m['city_id'] as String,
    name: m['name'] as String,
    state: m['state'] as String?,
    period: m['period'] as String,
    score: asInt(m['score']) ?? 0,
    rank: asInt(m['rank']) ?? 0,
    activeSites: asInt(m['active_sites']) ?? 0,
    burnEvents: asInt(m['burn_events']) ?? 0,
    medianDaysToClear: asDouble(m['median_days_to_clear']),
    pctVerifiedCleared: asDouble(m['pct_verified_cleared']),
    parts: {for (final e in ((m['parts'] as Map?) ?? const {}).entries) e.key as String: asDouble(e.value) ?? 0},
  );
}
