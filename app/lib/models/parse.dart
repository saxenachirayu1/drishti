import 'package:latlong2/latlong.dart';

double? asDouble(Object? v) => v == null ? null : (v as num).toDouble();

int? asInt(Object? v) => v == null ? null : (v as num).round();

DateTime? asDate(Object? v) => v == null ? null : DateTime.tryParse(v.toString());

/// Outer rings of a GeoJSON Polygon or MultiPolygon, as map points.
List<List<LatLng>> outerRings(Object? geojson) {
  if (geojson is! Map) return const [];
  final coords = geojson['coordinates'];
  List<LatLng> ring(List r) =>
      [for (final p in r) LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble())];
  switch (geojson['type']) {
    case 'Polygon':
      return [ring((coords as List).first as List)];
    case 'MultiPolygon':
      return [for (final poly in coords as List) ring((poly as List).first as List)];
    default:
      return const [];
  }
}
