import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/place.dart';
import '../models/site.dart';
import '../providers.dart';
import '../widgets/common.dart';
import 'site_detail_screen.dart';

enum SiteFilter { all, nearWater, highFire, notOnRecord }

/// National map that zooms to street level. Below zoom 8 each city is one
/// bubble with its site count; closer in, every site is a pin, and from
/// zoom 13 its outline is drawn.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const _india = LatLng(22.5, 79.0);
  final _map = MapController();
  double _zoom = 4.6;
  bool _satellite = false;
  bool _showFires = true;
  bool _showWards = true;
  SiteFilter _filter = SiteFilter.all;
  String? _cityId;

  void _goToCity(City? city) {
    setState(() => _cityId = city?.id);
    if (city == null) {
      _map.move(_india, 4.6);
    } else if (city.hasBounds) {
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds(LatLng(city.south!, city.west!), LatLng(city.north!, city.east!)),
        padding: const EdgeInsets.all(32),
      ));
    } else if (city.center != null) {
      _map.move(city.center!, 11);
    }
  }

  bool _passes(Site s) => switch (_filter) {
        SiteFilter.all => true,
        SiteFilter.nearWater => s.nearWater,
        SiteFilter.highFire => s.highFireRisk,
        SiteFilter.notOnRecord => !s.onOfficialRecord,
      };

  void _openSite(Site site) => showModalBottomSheet(
        context: context,
        builder: (_) => _SiteSheet(site: site),
      );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final cities = ref.watch(citiesProvider).value ?? const <City>[];
    final allSites = ref.watch(sitesProvider).value ?? const <Site>[];
    final fires = ref.watch(firesProvider).value ?? const [];
    final wards = ref.watch(wardsProvider).value ?? const [];
    final sites = allSites.where((x) => x.status != 'dismissed' && _passes(x)).toList();

    final scoped = _cityId == null ? allSites : allSites.where((x) => x.cityId == _cityId).toList();
    final found = scoped.where((x) => x.status != 'dismissed').toList();
    final notOnRecord = found.where((x) => !x.onOfficialRecord).length;
    final place = _cityId == null
        ? s.allIndia
        : cities.firstWhere((c) => c.id == _cityId, orElse: () => City(id: _cityId!, name: _cityId!)).name;

    final cityMode = _zoom < 8;

    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: _india,
          initialZoom: _zoom,
          minZoom: 3,
          maxZoom: 19,
          onPositionChanged: (camera, _) {
            if ((camera.zoom < 8) != (_zoom < 8) || (camera.zoom < 13) != (_zoom < 13) ||
                (camera.zoom < 11) != (_zoom < 11)) {
              setState(() => _zoom = camera.zoom);
            } else {
              _zoom = camera.zoom;
            }
          },
        ),
        children: [
          ...baseLayers(satellite: _satellite),
          if (_showWards && _zoom >= 11)
            PolygonLayer(polygons: [
              for (final w in wards)
                for (final ring in w.rings)
                  Polygon(
                    points: ring,
                    color: Colors.indigo.withValues(alpha: 0.04),
                    borderColor: Colors.indigo.withValues(alpha: 0.6),
                    borderStrokeWidth: 1.5,
                    label: w.wardNo == null ? w.name : '${s.ward} ${w.wardNo}',
                    labelStyle: const TextStyle(color: Colors.indigo, fontSize: 11),
                  ),
            ]),
          if (_zoom >= 13)
            PolygonLayer(polygons: [
              for (final site in sites)
                for (final ring in site.rings)
                  Polygon(
                    points: ring,
                    color: statusColor(site.status).withValues(alpha: 0.35),
                    borderColor: statusColor(site.status),
                    borderStrokeWidth: 2,
                  ),
            ]),
          if (_showFires && !cityMode)
            MarkerLayer(markers: [
              for (final f in fires)
                Marker(
                  point: f.point,
                  width: 22,
                  height: 22,
                  child: const Icon(Icons.local_fire_department, color: Colors.deepOrange, size: 20),
                ),
            ]),
          MarkerLayer(
            markers: cityMode
                ? [
                    for (final c in cities)
                      if (c.center != null)
                        Marker(
                          point: c.center!,
                          width: 64,
                          height: 64,
                          child: _CityBubble(
                            name: c.name,
                            count: sites.where((x) => x.cityId == c.id).length,
                            onTap: () => _goToCity(c),
                          ),
                        ),
                  ]
                : [
                    for (final site in sites)
                      if (site.point != null)
                        Marker(
                          point: site.point!,
                          width: 36,
                          height: 36,
                          alignment: Alignment.topCenter,
                          child: GestureDetector(
                            onTap: () => _openSite(site),
                            child: Icon(Icons.location_on, color: statusColor(site.status), size: 36,
                                shadows: const [Shadow(blurRadius: 3, color: Colors.black45)]),
                          ),
                        ),
                  ],
          ),
          mapAttribution(satellite: _satellite),
        ],
      ),
      // City chips, layer toggles and the pitch line.
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip(s.allIndia, _cityId == null, () => _goToCity(null)),
                for (final c in cities) _chip(c.name, _cityId == c.id, () => _goToCity(c)),
              ]),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip(s.all, _filter == SiteFilter.all, () => setState(() => _filter = SiteFilter.all)),
                _chip(s.nearWater, _filter == SiteFilter.nearWater,
                    () => setState(() => _filter = SiteFilter.nearWater)),
                _chip(s.highFireRisk, _filter == SiteFilter.highFire,
                    () => setState(() => _filter = SiteFilter.highFire)),
                _chip(s.notOnRecord, _filter == SiteFilter.notOnRecord,
                    () => setState(() => _filter = SiteFilter.notOnRecord)),
              ]),
            ),
            const SizedBox(height: 6),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(s.foundLine(found.length, notOnRecord, place),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ),
      Positioned(
        right: 8,
        bottom: 32,
        child: Card(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _toggle(Icons.satellite_alt, s.satellite, _satellite, () => setState(() => _satellite = !_satellite)),
            _toggle(Icons.local_fire_department, s.fires, _showFires, () => setState(() => _showFires = !_showFires)),
            _toggle(Icons.grid_on, s.wards, _showWards, () => setState(() => _showWards = !_showWards)),
            IconButton(
              tooltip: s.legend,
              icon: const Icon(Icons.info_outline),
              onPressed: () => showDialog(context: context, builder: (_) => const _LegendDialog()),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilterChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          backgroundColor: Theme.of(context).colorScheme.surface,
        ),
      );

  Widget _toggle(IconData icon, String tooltip, bool on, VoidCallback onTap) => IconButton(
        tooltip: tooltip,
        isSelected: on,
        icon: Icon(icon),
        color: on ? Theme.of(context).colorScheme.primary : null,
        onPressed: onTap,
      );
}

class _CityBubble extends StatelessWidget {
  const _CityBubble({required this.name, required this.count, required this.onTap});
  final String name;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFD32F2F),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
            ),
            child: Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          Text(name,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 3, color: Colors.white)])),
        ]),
      );
}

class _SiteSheet extends ConsumerWidget {
  const _SiteSheet({required this.site});
  final Site site;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${s.site} ${site.id}', style: Theme.of(context).textTheme.titleLarge)),
          StatusChip(site.status),
        ]),
        const SizedBox(height: 8),
        InfoRow(s.ward, site.wardNo == null ? (site.wardName ?? '-') : '${site.wardNo} · ${site.wardName ?? ''}'),
        InfoRow(s.area, fmtArea(site.areaM2)),
        InfoRow(s.lastSeen, fmtDate(site.lastSeen)),
        InfoRow(s.fireRisk, '${site.fireRisk}/100'),
        if (site.nearWater) InfoRow(s.nearWater, '✓'),
        InfoRow('', site.onOfficialRecord ? s.onRecord : s.notOnRecord),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => SiteDetailScreen(siteId: site.id)));
            },
            child: Text(s.open),
          ),
        ),
      ]),
    );
  }
}

class _LegendDialog extends ConsumerWidget {
  const _LegendDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    Widget row(Widget icon, String text) =>
        Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [icon, const SizedBox(width: 12), Text(text)]));
    return AlertDialog(
      title: Text(s.legend),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final st in ['active', 'complaint_sent', 'cleanup_reported', 'cleared'])
          row(Icon(Icons.location_on, color: statusColor(st)), s.status(st)),
        row(const Icon(Icons.local_fire_department, color: Colors.deepOrange), s.fireEvents),
        row(const Icon(Icons.crop_square, color: Colors.indigo), s.wards),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    );
  }
}
