import 'package:latlong2/latlong.dart';

import 'parse.dart';

/// A row of the `site_map` view: one physical dump tracked over time.
class Site {
  const Site({
    required this.id,
    required this.cityId,
    required this.status,
    required this.areaM2,
    required this.fireRisk,
    required this.nearWater,
    required this.onOfficialRecord,
    this.wardId,
    this.wardNo,
    this.wardName,
    this.officerEmail,
    this.confidence,
    this.growth,
    this.firstSeen,
    this.lastSeen,
    this.clearedCandidate = false,
    this.lat,
    this.lng,
    this.rings = const [],
    this.dismissedReason,
    this.reviewedAt,
  });

  final String id;
  final String cityId;
  final String? wardId;
  final int? wardNo;
  final String? wardName;
  final String? officerEmail;
  final String status;
  final double areaM2;
  final int fireRisk;
  final bool nearWater;
  final double? confidence;
  final String? growth;
  final DateTime? firstSeen;
  final DateTime? lastSeen;
  final bool clearedCandidate;
  final bool onOfficialRecord;
  final double? lat;
  final double? lng;
  final List<List<LatLng>> rings;
  final String? dismissedReason;
  final DateTime? reviewedAt;

  LatLng? get point => lat == null || lng == null ? null : LatLng(lat!, lng!);

  bool get highFireRisk => fireRisk >= 60;

  factory Site.fromMap(Map<String, dynamic> m) => Site(
    id: m['id'] as String,
    cityId: m['city_id'] as String,
    wardId: m['ward_id'] as String?,
    wardNo: asInt(m['ward_no']),
    wardName: m['ward_name'] as String?,
    officerEmail: m['officer_email'] as String?,
    status: m['status'] as String? ?? 'active',
    areaM2: asDouble(m['area_m2']) ?? 0,
    fireRisk: asInt(m['fire_risk']) ?? 0,
    nearWater: m['near_water'] as bool? ?? false,
    confidence: asDouble(m['confidence']),
    growth: m['growth'] as String?,
    firstSeen: asDate(m['first_seen']),
    lastSeen: asDate(m['last_seen']),
    clearedCandidate: m['cleared_candidate'] as bool? ?? false,
    onOfficialRecord: m['on_official_record'] as bool? ?? false,
    lat: asDouble(m['lat']),
    lng: asDouble(m['lng']),
    rings: outerRings(m['geojson']),
    dismissedReason: m['dismissed_reason'] as String?,
    reviewedAt: asDate(m['reviewed_at']),
  );
}

/// A row of `detection_timeline`: one sighting of a site in one scene.
class Detection {
  const Detection({
    required this.id,
    required this.siteId,
    this.sceneId,
    this.detectedOn,
    this.areaM2,
    this.confidence,
    this.thumbUrl,
    this.rings = const [],
  });

  final String id;
  final String siteId;
  final String? sceneId;
  final DateTime? detectedOn;
  final double? areaM2;
  final double? confidence;
  final String? thumbUrl;
  final List<List<LatLng>> rings;

  factory Detection.fromMap(Map<String, dynamic> m) => Detection(
    id: m['id'] as String,
    siteId: m['site_id'] as String,
    sceneId: m['scene_id'] as String?,
    detectedOn: asDate(m['detected_on']),
    areaM2: asDouble(m['area_m2']),
    confidence: asDouble(m['confidence']),
    thumbUrl: m['thumb_url'] as String?,
    rings: outerRings(m['geojson']),
  );
}

/// A row of `fire_map`: a NASA FIRMS hotspot.
class FireEvent {
  const FireEvent({
    required this.id,
    required this.lat,
    required this.lng,
    this.cityId,
    this.siteId,
    this.detectedAt,
    this.frp,
    this.confidence,
    this.source,
  });

  final String id;
  final String? cityId;
  final String? siteId;
  final DateTime? detectedAt;
  final double? frp;
  final String? confidence;
  final String? source;
  final double lat;
  final double lng;

  LatLng get point => LatLng(lat, lng);

  factory FireEvent.fromMap(Map<String, dynamic> m) => FireEvent(
    id: m['id'] as String,
    cityId: m['city_id'] as String?,
    siteId: m['site_id'] as String?,
    detectedAt: asDate(m['detected_at']),
    frp: asDouble(m['frp']),
    confidence: m['confidence']?.toString(),
    source: m['source'] as String?,
    lat: asDouble(m['lat'])!,
    lng: asDouble(m['lng'])!,
  );
}
