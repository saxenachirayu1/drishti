import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/place.dart';
import '../models/site.dart';
import '../providers.dart';
import '../services/complaint_drafter.dart';
import '../widgets/common.dart';
import 'complaint_screen.dart';

class SiteDetailScreen extends ConsumerWidget {
  const SiteDetailScreen({super.key, required this.siteId});
  final String siteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final site = ref.watch(siteProvider(siteId));
    return Scaffold(
      appBar: AppBar(title: Text('${s.site} $siteId')),
      body: AsyncView(
        site,
        onRetry: () => ref.invalidate(siteProvider(siteId)),
        builder: (site) => site == null
            ? const Center(child: EmptyNote())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(padding: const EdgeInsets.all(12), children: [
                    _Facts(site: site),
                    _Timeline(site: site),
                    _Fires(siteId: site.id),
                    _Complaints(site: site),
                    _Verifications(site: site),
                  ]),
                ),
              ),
      ),
    );
  }
}

class _Facts extends ConsumerWidget {
  const _Facts({required this.site});
  final Site site;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final profile = ref.watch(profileProvider).value;
    final cities = ref.watch(citiesProvider).value ?? const <City>[];
    final city = cities.where((c) => c.id == site.cityId).firstOrNull;
    return SectionCard(
      title: '${city?.name ?? site.cityId} · ${s.ward} ${site.wardNo ?? '-'} ${site.wardName ?? ''}',
      trailing: StatusChip(site.status),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InfoRow(s.area, fmtArea(site.areaM2)),
        InfoRow(s.firstSeen, fmtDate(site.firstSeen)),
        InfoRow(s.lastSeen, fmtDate(site.lastSeen)),
        if (site.growth != null) InfoRow(s.change, site.growth!),
        if (site.confidence != null) InfoRow(s.confidence, '${(site.confidence! * 100).round()}%'),
        InfoRow(s.officer, site.officerEmail ?? '-'),
        InfoRow('', site.onOfficialRecord ? s.onRecord : s.notOnRecord),
        if (site.nearWater)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              const Icon(Icons.water_drop, color: Colors.blue, size: 18),
              const SizedBox(width: 6),
              Text(s.nearWater),
            ]),
          ),
        MeterBar(
          label: s.fireRisk,
          fraction: site.fireRisk / 100,
          trailing: '${site.fireRisk}/100',
          color: site.highFireRisk ? Colors.deepOrange : Colors.amber,
        ),
        if (site.point != null)
          TextButton.icon(
            icon: const Icon(Icons.map_outlined),
            label: Text('${s.openInMaps} (${site.lat!.toStringAsFixed(5)}, ${site.lng!.toStringAsFixed(5)})'),
            onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps?q=${site.lat},${site.lng}')),
          ),
        if (profile?.canAct ?? false) ...[
          const Divider(),
          Text(s.changeStatus, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final st in ['active', 'complaint_sent', 'cleanup_reported', 'cleared', 'dismissed'])
              ChoiceChip(
                label: Text(s.status(st)),
                selected: site.status == st,
                onSelected: site.status == st
                    ? null
                    : (_) async {
                        final ok = await guarded(context, () => ref.read(actionsProvider).setSiteStatus(site, st),
                            success: s.statusUpdated);
                        if (ok) ref.invalidate(sitesProvider);
                      },
              ),
          ]),
        ],
      ]),
    );
  }
}

/// The before/after slider: each satellite pass that saw the site, with its outline.
class _Timeline extends ConsumerStatefulWidget {
  const _Timeline({required this.site});
  final Site site;

  @override
  ConsumerState<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends ConsumerState<_Timeline> {
  int? _index;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final dets = ref.watch(timelineProvider(widget.site.id));
    return SectionCard(
      title: s.timeline,
      child: AsyncView(dets, builder: (dets) {
        if (dets.isEmpty) return EmptyNote(text: s.noDetections);
        final i = (_index ?? dets.length - 1).clamp(0, dets.length - 1);
        final d = dets[i];
        final first = dets.first;
        final firstArea = first.areaM2 ?? 0;
        final area = d.areaM2 ?? 0;
        final pct = firstArea > 0 ? ((area - firstArea) / firstArea * 100).round() : 0;
        final center = widget.site.point;
        final allPoints = [for (final x in dets) for (final r in x.rings) ...r];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.timelineHint, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (center != null)
            SizedBox(
              height: 280,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 17,
                    initialCameraFit: allPoints.length >= 3
                        ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(allPoints), padding: const EdgeInsets.all(48))
                        : null,
                  ),
                  children: [
                    ...baseLayers(satellite: true),
                    PolygonLayer(polygons: [
                      for (final r in first.rings)
                        Polygon(points: r, borderColor: Colors.yellowAccent, borderStrokeWidth: 2),
                      for (final r in d.rings)
                        Polygon(
                          points: r,
                          color: Colors.red.withValues(alpha: 0.35),
                          borderColor: Colors.redAccent,
                          borderStrokeWidth: 2.5,
                        ),
                    ]),
                    mapAttribution(satellite: true),
                  ],
                ),
              ),
            ),
          if (d.thumbUrl != null || first.thumbUrl != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              for (final x in [first, d])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(children: [
                      if (x.thumbUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(x.thumbUrl!, height: 140, fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const SizedBox(height: 140, child: Icon(Icons.broken_image))),
                        ),
                      Text(fmtDate(x.detectedOn), style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ),
            ]),
          ],
          if (dets.length > 1)
            Slider(
              value: i.toDouble(),
              min: 0,
              max: (dets.length - 1).toDouble(),
              divisions: dets.length - 1,
              label: fmtDate(d.detectedOn),
              onChanged: (v) => setState(() => _index = v.round()),
            ),
          Wrap(spacing: 16, children: [
            Text(fmtDate(d.detectedOn), style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(fmtArea(area)),
            Text(i == 0 ? s.firstSighting : '${pct >= 0 ? '+' : ''}$pct% ${s.sinceFirst}',
                style: TextStyle(color: pct > 0 ? Colors.red : Colors.green)),
            if (d.confidence != null) Text('${s.confidence}: ${(d.confidence! * 100).round()}%'),
          ]),
          const SizedBox(height: 12),
          _AreaBars(areas: [for (final x in dets) x.areaM2 ?? 0], selected: i),
        ]);
      }),
    );
  }
}

class _AreaBars extends StatelessWidget {
  const _AreaBars({required this.areas, required this.selected});
  final List<double> areas;
  final int selected;

  @override
  Widget build(BuildContext context) {
    final maxA = areas.fold<double>(1, (m, a) => a > m ? a : m);
    return SizedBox(
      height: 60,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < areas.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: FractionallySizedBox(
                heightFactor: (areas[i] / maxA).clamp(0.05, 1),
                child: Container(
                  decoration: BoxDecoration(
                    color: i == selected ? Colors.redAccent : Colors.redAccent.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _Fires extends ConsumerWidget {
  const _Fires({required this.siteId});
  final String siteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return SectionCard(
      title: s.fireEvents,
      child: AsyncView(ref.watch(siteFiresProvider(siteId)), builder: (fires) {
        if (fires.isEmpty) return const EmptyNote();
        return Column(children: [
          for (final f in fires)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.local_fire_department, color: Colors.deepOrange),
              title: Text(fmtDateTime(f.detectedAt)),
              subtitle: Text('${f.source ?? 'VIIRS'} · FRP ${f.frp?.toStringAsFixed(1) ?? '-'} MW'
                  ' · ${s.confidence}: ${f.confidence ?? '-'}'),
            ),
        ]);
      }),
    );
  }
}

class _Complaints extends ConsumerWidget {
  const _Complaints({required this.site});
  final Site site;

  Future<void> _draft(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final language = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(s.chooseLanguage),
        children: [
          for (final l in ComplaintDrafter.languages)
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, l), child: Text(l == 'Hindi' ? 'हिन्दी (Hindi)' : l)),
        ],
      ),
    );
    if (language == null || !context.mounted) return;
    final city = (ref.read(citiesProvider).value ?? const <City>[]).where((c) => c.id == site.cityId).firstOrNull;
    try {
      final c = await ref.read(actionsProvider).draftComplaint(site, city: city, language: language);
      ref.invalidate(siteComplaintsProvider(site.id));
      ref.invalidate(allComplaintsProvider);
      if (context.mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ComplaintScreen(complaintId: c.id)));
      }
    } catch (e) {
      if (context.mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final canAct = ref.watch(profileProvider).value?.canAct ?? false;
    return SectionCard(
      title: s.complaints,
      trailing: canAct
          ? FilledButton.icon(
              icon: const Icon(Icons.edit_document),
              label: Text(s.draftComplaint),
              onPressed: () => _draft(context, ref),
            )
          : null,
      child: AsyncView(ref.watch(siteComplaintsProvider(site.id)), builder: (list) {
        if (list.isEmpty) return const EmptyNote();
        return Column(children: [
          for (final c in list)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text('${s.complaint} ${c.id.length > 8 ? c.id.substring(0, 8) : c.id} · ${c.language}'),
              subtitle: Text(fmtDateTime(c.sentAt ?? c.createdAt)),
              trailing: StatusChip(c.status),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => ComplaintScreen(complaintId: c.id))),
            ),
        ]);
      }),
    );
  }
}

class _Verifications extends ConsumerWidget {
  const _Verifications({required this.site});
  final Site site;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final canAct = ref.watch(profileProvider).value?.canAct ?? false;
    return SectionCard(
      title: s.verification,
      trailing: canAct
          ? OutlinedButton.icon(
              icon: const Icon(Icons.satellite_alt),
              label: Text(s.checkCleanup),
              onPressed: () async {
                try {
                  final result = await ref.read(actionsProvider).verifySite(site);
                  ref.invalidate(verificationsProvider(site.id));
                  ref.invalidate(sitesProvider);
                  if (context.mounted) toast(context, s.result(result));
                } catch (e) {
                  if (context.mounted) toast(context, '$e');
                }
              },
            )
          : null,
      child: AsyncView(ref.watch(verificationsProvider(site.id)), builder: (list) {
        if (list.isEmpty) return const EmptyNote();
        return Column(children: [
          for (final v in list)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.fact_check_outlined),
              title: Text(fmtDateTime(v.checkedAt)),
              trailing: StatusChip(v.result, label: s.result(v.result)),
            ),
        ]);
      }),
    );
  }
}
