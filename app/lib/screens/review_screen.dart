import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/action.dart';
import '../models/place.dart';
import '../models/site.dart';
import '../providers.dart';
import '../widgets/common.dart';
import 'site_detail_screen.dart';

/// Admin review (A-22): new detections, citizen reports, and user access.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        TabBar(isScrollable: true, tabs: [Tab(text: s.newDetections), Tab(text: s.reports), Tab(text: s.users)]),
        const Expanded(child: TabBarView(children: [_DetectionsTab(), _ReportsTab(), _UsersTab()])),
      ]),
    );
  }
}

/// Sites nobody has looked at yet, low-confidence ones included, so false
/// positives are caught before the demo.
class _DetectionsTab extends ConsumerWidget {
  const _DetectionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return AsyncView(ref.watch(unreviewedSitesProvider), onRetry: () => ref.invalidate(unreviewedSitesProvider),
        builder: (list) {
      if (list.isEmpty) return const Center(child: EmptyNote());
      return ListView(padding: const EdgeInsets.all(12), children: [
        for (final site in list)
          Card(
            child: ListTile(
              leading: Icon(Icons.location_on, color: statusColor(site.status)),
              title: Text('${s.site} ${site.id} · ${s.ward} ${site.wardNo ?? '-'}'),
              subtitle: Text('${fmtArea(site.areaM2)} · ${s.firstSeen} ${fmtDate(site.firstSeen)} · '
                  '${s.confidence} ${site.confidence == null ? '-' : '${(site.confidence! * 100).round()}%'}'),
              onTap: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => SiteDetailScreen(siteId: site.id))),
              trailing: Wrap(spacing: 4, children: [
                IconButton(
                  tooltip: s.confirmSite,
                  icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                  onPressed: () async {
                    final ok = await guarded(context, () => ref.read(repoProvider).markReviewed(site.id),
                        success: s.reviewed);
                    if (ok) ref.invalidate(unreviewedSitesProvider);
                  },
                ),
                IconButton(
                  tooltip: s.dismiss,
                  icon: const Icon(Icons.block, color: Colors.red),
                  onPressed: () => dismissSite(context, ref, site),
                ),
              ]),
            ),
          ),
      ]);
    });
  }
}

double _metres(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
  final dp = (lat2 - lat1) * math.pi / 180, dl = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

class _ReportsTab extends ConsumerWidget {
  const _ReportsTab();

  Future<void> _link(BuildContext context, WidgetRef ref, CitizenReport r) async {
    final s = ref.read(stringsProvider);
    final sites = [...(ref.read(sitesProvider).value ?? const <Site>[]).where((x) => x.point != null)];
    if (r.point != null) {
      sites.sort((a, b) => _metres(r.lat!, r.lng!, a.lat!, a.lng!).compareTo(_metres(r.lat!, r.lng!, b.lat!, b.lng!)));
    }
    final picked = await showDialog<Site>(
      context: context,
      builder: (ctx) => SimpleDialog(title: Text(s.pickSite), children: [
        for (final x in sites.take(6))
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, x),
            child: Text('${x.id} · ${s.ward} ${x.wardNo ?? '-'}'
                '${r.point == null ? '' : ' · ${_metres(r.lat!, r.lng!, x.lat!, x.lng!).round()} m'}'),
          ),
      ]),
    );
    if (picked == null || !context.mounted) return;
    final ok = await guarded(context, () async {
      await ref.read(repoProvider).reviewReport(r.id, status: 'matched', linkedSiteId: picked.id);
      await ref.read(repoProvider).audit('match', 'citizen_report', r.id, {'site_id': picked.id});
    });
    if (ok) ref.invalidate(allReportsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return AsyncView(ref.watch(allReportsProvider), onRetry: () => ref.invalidate(allReportsProvider), builder: (list) {
      if (list.isEmpty) return const Center(child: EmptyNote());
      return RefreshIndicator(
        onRefresh: () async => ref.invalidate(allReportsProvider),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          for (final r in list)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(right: 12), child: ReportPhoto(stored: r.photoUrl, size: 80)),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(r.note ?? '-', style: const TextStyle(fontWeight: FontWeight.w600))),
                        StatusChip(r.status),
                      ]),
                      const SizedBox(height: 4),
                      Text('${fmtDateTime(r.createdAt)} · ${r.lat?.toStringAsFixed(5)}, ${r.lng?.toStringAsFixed(5)}',
                          style: Theme.of(context).textTheme.bodySmall),
                      if (r.linkedSiteId != null)
                        TextButton(
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => SiteDetailScreen(siteId: r.linkedSiteId!))),
                          child: Text('${s.site} ${r.linkedSiteId}'),
                        ),
                      if (r.status != 'rejected')
                        Wrap(spacing: 8, children: [
                          OutlinedButton(onPressed: () => _link(context, ref, r), child: Text(s.markMatched)),
                          TextButton(
                            onPressed: () async {
                              final ok = await guarded(context, () async {
                                await ref.read(repoProvider).reviewReport(r.id, status: 'rejected');
                                await ref.read(repoProvider).audit('reject', 'citizen_report', r.id);
                              });
                              if (ok) ref.invalidate(allReportsProvider);
                            },
                            child: Text(s.reject),
                          ),
                        ]),
                    ]),
                  ),
                ]),
              ),
            ),
        ]),
      );
    });
  }
}

/// Roles and home cities are set only here, by an admin (A-08, A-18).
class _UsersTab extends ConsumerWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final me = ref.watch(userIdProvider);
    final cities = ref.watch(citiesProvider).value ?? const <City>[];
    Future<void> save(Profile p, String role, String? city) async {
      final ok = await guarded(context, () => ref.read(repoProvider).setUserAccess(p.userId, role, city),
          success: s.saved);
      if (ok) ref.invalidate(profilesProvider);
    }

    return AsyncView(ref.watch(profilesProvider), onRetry: () => ref.invalidate(profilesProvider), builder: (list) {
      return ListView(padding: const EdgeInsets.all(12), children: [
        for (final p in list)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 240,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.fullName ?? p.email ?? p.userId),
                    subtitle: Text(p.email ?? ''),
                  ),
                ),
                DropdownButton<String>(
                  value: p.role,
                  items: [
                    for (final r in ['citizen', 'officer', 'board', 'admin'])
                      DropdownMenuItem(value: r, child: Text(s.roleName(r))),
                  ],
                  onChanged: p.userId == me ? null : (role) => role == null ? null : save(p, role, p.cityId),
                ),
                DropdownButton<String?>(
                  value: p.cityId,
                  hint: Text(s.homeCity),
                  items: [
                    DropdownMenuItem(value: null, child: Text(s.anyCity)),
                    for (final c in cities) DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (city) => save(p, p.role, city),
                ),
              ]),
            ),
          ),
      ]);
    });
  }
}
