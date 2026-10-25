import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/l10n.dart';
import '../models/place.dart';
import '../models/site.dart';
import '../providers.dart';
import '../widgets/common.dart';
import 'site_detail_screen.dart';

const _statuses = ['active', 'complaint_sent', 'cleanup_reported', 'cleared'];

/// The map's filters (A-13). They combine: a site shows only if it passes all.
class SiteFilters {
  const SiteFilters({
    this.statuses = const {..._statuses},
    this.wardId,
    this.sinceDays,
    this.nearWater = false,
    this.notOnRecord = false,
    this.minFireRisk = 0,
  });

  final Set<String> statuses;
  final String? wardId;
  final int? sinceDays;
  final bool nearWater;
  final bool notOnRecord;
  final int minFireRisk;

  bool get isDefault =>
      statuses.length == _statuses.length && wardId == null && sinceDays == null && !nearWater && !notOnRecord &&
      minFireRisk == 0;

  bool passes(Site s) {
    if (!statuses.contains(s.status)) return false;
    if (wardId != null && s.wardId != wardId) return false;
    if (sinceDays != null &&
        (s.firstSeen == null || s.firstSeen!.isBefore(DateTime.now().subtract(Duration(days: sinceDays!))))) {
      return false;
    }
    if (nearWater && !s.nearWater) return false;
    if (notOnRecord && s.onOfficialRecord) return false;
    return s.fireRisk >= minFireRisk;
  }

  SiteFilters copy({
    Set<String>? statuses,
    String? Function()? wardId,
    int? Function()? sinceDays,
    bool? nearWater,
    bool? notOnRecord,
    int? minFireRisk,
  }) =>
      SiteFilters(
        statuses: statuses ?? this.statuses,
        wardId: wardId == null ? this.wardId : wardId(),
        sinceDays: sinceDays == null ? this.sinceDays : sinceDays(),
        nearWater: nearWater ?? this.nearWater,
        notOnRecord: notOnRecord ?? this.notOnRecord,
        minFireRisk: minFireRisk ?? this.minFireRisk,
      );
}

/// Groups points that fall in the same ~70 px square at this zoom (A-11).
List<List<Site>> clusterSites(List<Site> sites, double zoom, {double cellPx = 70}) {
  final degPerPx = 360 / (256 * math.pow(2, zoom));
  final cell = cellPx * degPerPx;
  final groups = <(int, int), List<Site>>{};
  for (final s in sites) {
    if (s.point == null) continue;
    groups.putIfAbsent(((s.lat! / cell).floor(), (s.lng! / cell).floor()), () => []).add(s);
  }
  return groups.values.toList();
}

/// Pin size grows with the dump's area: 28 px for small sites, up to 56 px.
double pinSize(double areaM2) => (24 + math.sqrt(areaM2) / 3).clamp(28, 56).toDouble();

/// National map that zooms to street level. Below zoom 8 each city is one
/// bubble with its site count; closer in, nearby pins cluster, and from zoom 13
/// each site's outline is drawn.
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
  bool _showSites = true;
  bool _showFires = true;
  bool _showWards = true;
  SiteFilters _filters = const SiteFilters();
  String? _cityId;

  void _goToCity(City? city) {
    setState(() {
      _cityId = city?.id;
      _filters = _filters.copy(wardId: () => null);
    });
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

  void _fitTo(List<Site> sites) {
    final pts = [for (final s in sites) ?s.point];
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _map.move(pts.single, 16);
    } else {
      _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(80), maxZoom: 16));
    }
  }

  void _openSite(Site site) => showModalBottomSheet(context: context, builder: (_) => _SiteSheet(site: site));

  Future<void> _editFilters(List<Site> scoped) async {
    final wards = (ref.read(wardsProvider).value ?? const <Ward>[])
        .where((w) => _cityId == null || w.cityId == _cityId)
        .toList();
    final picked = await showModalBottomSheet<SiteFilters>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(initial: _filters, wards: wards, sites: scoped),
    );
    if (picked != null) setState(() => _filters = picked);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final cities = ref.watch(citiesProvider).value ?? const <City>[];
    final allSites = ref.watch(sitesProvider).value ?? const <Site>[];
    final fires = ref.watch(firesProvider).value ?? const [];
    final wards = ref.watch(wardsProvider).value ?? const <Ward>[];
    final highlight = ref.watch(highlightProvider).toSet();
    final offline = ref.watch(repoProvider).offline;

    // The assistant asked for some sites: frame them once the map is showing.
    ref.listen(highlightProvider, (_, ids) {
      if (ids.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _fitTo([for (final x in allSites) if (ids.contains(x.id)) x]));
    });

    final scoped = _cityId == null ? allSites : allSites.where((x) => x.cityId == _cityId).toList();
    final visible = scoped.where((x) => x.status != 'dismissed').toList();
    final shown = visible.where(_filters.passes).toList();
    final notOnRecord = visible.where((x) => !x.onOfficialRecord).length;
    final place = _cityId == null
        ? s.allIndia
        : cities.firstWhere((c) => c.id == _cityId, orElse: () => City(id: _cityId!, name: _cityId!)).name;

    final cityMode = _zoom < 8;
    final mapSites = _cityId == null ? allSites.where((x) => x.status != 'dismissed' && _filters.passes(x)).toList() : shown;

    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: _india,
          initialZoom: _zoom,
          minZoom: 3,
          maxZoom: 19,
          onPositionChanged: (camera, _) {
            if (camera.zoom.floor() != _zoom.floor()) {
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
          if (_showSites && _zoom >= 13)
            PolygonLayer(polygons: [
              for (final site in mapSites)
                for (final ring in site.rings)
                  Polygon(
                    points: ring,
                    color: statusColor(site.status).withValues(alpha: 0.35),
                    borderColor: highlight.contains(site.id) ? Colors.purpleAccent : statusColor(site.status),
                    borderStrokeWidth: highlight.contains(site.id) ? 4 : 2,
                  ),
            ]),
          if (_showFires && !cityMode)
            MarkerLayer(markers: [
              for (final f in fires)
                Marker(
                  point: f.point,
                  width: 22,
                  height: 22,
                  child: Icon(Icons.local_fire_department, color: Colors.deepOrange, size: 20, semanticLabel: s.fires),
                ),
            ]),
          if (_showSites)
            MarkerLayer(
              markers: cityMode
                  ? [
                      for (final c in cities)
                        if (c.center != null)
                          Marker(
                            point: c.center!,
                            width: 72,
                            height: 64,
                            child: _Bubble(
                              label: c.name,
                              count: mapSites.where((x) => x.cityId == c.id).length,
                              onTap: () => _goToCity(c),
                            ),
                          ),
                    ]
                  : [
                      for (final group in clusterSites(mapSites, _zoom))
                        if (group.length > 1 && _zoom < 16)
                          Marker(
                            point: LatLng(group.map((x) => x.lat!).reduce((a, b) => a + b) / group.length,
                                group.map((x) => x.lng!).reduce((a, b) => a + b) / group.length),
                            width: 48,
                            height: 48,
                            child: _Bubble(
                              count: group.length,
                              onTap: () => _fitTo(group),
                              semantic: '${group.length} ${s.sitesShown}, ${s.zoomIn}',
                            ),
                          )
                        else
                          for (final site in group)
                            Marker(
                              point: site.point!,
                              width: pinSize(site.areaM2) + 8,
                              height: pinSize(site.areaM2) + 8,
                              alignment: Alignment.topCenter,
                              child: GestureDetector(
                                onTap: () => _openSite(site),
                                child: Icon(
                                  Icons.location_on,
                                  color: highlight.contains(site.id) ? Colors.purple : statusColor(site.status),
                                  size: pinSize(site.areaM2) + (highlight.contains(site.id) ? 8 : 0),
                                  semanticLabel: '${s.site} ${site.id}, ${s.status(site.status)}',
                                  shadows: const [Shadow(blurRadius: 3, color: Colors.black45)],
                                ),
                              ),
                            ),
                    ],
            ),
          mapAttribution(satellite: _satellite),
        ],
      ),
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
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ActionChip(
                avatar: Icon(_filters.isDefault ? Icons.filter_list : Icons.filter_alt),
                label: Text('${s.filters} · ${shown.length} ${s.sitesShown}'),
                onPressed: () => _editFilters(scoped),
              ),
              if (!_filters.isDefault)
                ActionChip(label: Text(s.clearFilters), onPressed: () => setState(() => _filters = const SiteFilters())),
              if (highlight.isNotEmpty)
                InputChip(
                  avatar: const Icon(Icons.auto_awesome, size: 16),
                  label: Text('${highlight.length} ${s.sitesShown}'),
                  onDeleted: () => ref.read(highlightProvider.notifier).set(const []),
                ),
            ]),
            const SizedBox(height: 6),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(s.foundLine(visible.length, notOnRecord, place),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: offline,
              builder: (_, isOffline, _) => isOffline
                  ? Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.cloud_off, size: 16),
                          const SizedBox(width: 6),
                          Text(s.offlineData),
                        ]),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ]),
        ),
      ),
      Positioned(
        right: 8,
        bottom: 32,
        child: Card(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _toggle(Icons.satellite_alt, '${s.satellite} / ${s.streets}', _satellite,
                () => setState(() => _satellite = !_satellite)),
            _toggle(Icons.location_on, s.sitesLayer, _showSites, () => setState(() => _showSites = !_showSites)),
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

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.initial, required this.wards, required this.sites});
  final SiteFilters initial;
  final List<Ward> wards;
  final List<Site> sites;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late SiteFilters _f = widget.initial;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final count = widget.sites.where((x) => x.status != 'dismissed' && _f.passes(x)).length;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(s.filters, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(s.statusLabel, style: Theme.of(context).textTheme.labelLarge),
            Wrap(spacing: 6, children: [
              for (final st in _statuses)
                FilterChip(
                  label: Text(s.status(st)),
                  selected: _f.statuses.contains(st),
                  onSelected: (on) => setState(() => _f = _f.copy(
                      statuses: on ? {..._f.statuses, st} : ({..._f.statuses}..remove(st)))),
                ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _f.wardId,
              decoration: InputDecoration(labelText: s.ward),
              items: [
                DropdownMenuItem(value: null, child: Text(s.anyWard)),
                for (final w in widget.wards)
                  DropdownMenuItem(value: w.id, child: Text('${s.ward} ${w.wardNo ?? ''} · ${w.name ?? ''}')),
              ],
              onChanged: (v) => setState(() => _f = _f.copy(wardId: () => v)),
            ),
            const SizedBox(height: 12),
            Text(s.firstSeenSince, style: Theme.of(context).textTheme.labelLarge),
            Wrap(spacing: 6, children: [
              for (final (days, label) in [(null, s.anyTime), (30, s.last30), (90, s.last90), (180, s.last180)])
                ChoiceChip(
                  label: Text(label),
                  selected: _f.sinceDays == days,
                  onSelected: (_) => setState(() => _f = _f.copy(sinceDays: () => days)),
                ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.nearWater),
              value: _f.nearWater,
              onChanged: (v) => setState(() => _f = _f.copy(nearWater: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.notOnRecord),
              value: _f.notOnRecord,
              onChanged: (v) => setState(() => _f = _f.copy(notOnRecord: v)),
            ),
            Text('${s.fireRiskAbove}: ${_f.minFireRisk}', style: Theme.of(context).textTheme.labelLarge),
            Slider(
              value: _f.minFireRisk.toDouble(),
              max: 100,
              divisions: 20,
              label: '${_f.minFireRisk}',
              onChanged: (v) => setState(() => _f = _f.copy(minFireRisk: v.round())),
            ),
            const SizedBox(height: 8),
            Row(children: [
              TextButton(onPressed: () => setState(() => _f = const SiteFilters()), child: Text(s.clearFilters)),
              const Spacer(),
              FilledButton(onPressed: () => Navigator.pop(context, _f), child: Text('$count ${s.sitesShown}')),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.count, required this.onTap, this.label, this.semantic});
  final int count;
  final VoidCallback onTap;
  final String? label;
  final String? semantic;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semantic ?? '${label ?? ''} $count',
        child: GestureDetector(
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
            if (label != null)
              Text(label!,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 3, color: Colors.white)])),
          ]),
        ),
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
        if (site.confidence != null) InfoRow(s.confidence, '${(site.confidence! * 100).round()}%'),
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
    Widget row(Widget icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [icon, const SizedBox(width: 12), Text(text)]));
    return AlertDialog(
      title: Text(s.legend),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final st in _statuses) row(Icon(Icons.location_on, color: statusColor(st)), s.status(st)),
        row(const Icon(Icons.local_fire_department, color: Colors.deepOrange), s.fireEvents),
        row(const Icon(Icons.crop_square, color: Colors.indigo), s.wards),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(s.ok))],
    );
  }
}
