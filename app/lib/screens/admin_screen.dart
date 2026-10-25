import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/action.dart';
import '../models/place.dart';
import '../models/site.dart';
import '../providers.dart';
import '../widgets/common.dart';
import 'complaint_screen.dart';
import 'site_detail_screen.dart';

/// Officials' dashboard: citizen reports, complaints, pipeline runs, users.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final profile = ref.watch(profileProvider).value;
    final isAdmin = profile?.isAdmin ?? false;
    return DefaultTabController(
      length: isAdmin ? 4 : 3,
      child: Column(children: [
        TabBar(isScrollable: true, tabs: [
          Tab(text: s.reports),
          Tab(text: s.complaints),
          Tab(text: s.pipeline),
          if (isAdmin) Tab(text: s.users),
        ]),
        Expanded(
          child: TabBarView(children: [
            const _ReportsTab(),
            const _ComplaintsTab(),
            const _PipelineTab(),
            if (isAdmin) const _UsersTab(),
          ]),
        ),
      ]),
    );
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
    final canAct = ref.watch(profileProvider).value?.canAct ?? false;
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
                  if (r.photoUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(r.photoUrl!, width: 80, height: 80, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(Icons.broken_image)),
                      ),
                    ),
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
                      if (canAct && r.status != 'rejected')
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

class _ComplaintsTab extends ConsumerWidget {
  const _ComplaintsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return AsyncView(ref.watch(allComplaintsProvider), onRetry: () => ref.invalidate(allComplaintsProvider),
        builder: (list) {
      if (list.isEmpty) return const Center(child: EmptyNote());
      return RefreshIndicator(
        onRefresh: () async => ref.invalidate(allComplaintsProvider),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          for (final c in list)
            Card(
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text('${s.site} ${c.siteId} · ${c.language}'),
                subtitle: Text(c.draftText.split('\n').where((l) => l.trim().isNotEmpty).skip(2).firstOrNull ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: StatusChip(c.status),
                onTap: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ComplaintScreen(complaintId: c.id))),
              ),
            ),
        ]),
      );
    });
  }
}

class _PipelineTab extends ConsumerStatefulWidget {
  const _PipelineTab();

  @override
  ConsumerState<_PipelineTab> createState() => _PipelineTabState();
}

class _PipelineTabState extends ConsumerState<_PipelineTab> {
  String? _cityId;
  String _kind = 'detect';

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final canAct = ref.watch(profileProvider).value?.canAct ?? false;
    final cities = ref.watch(citiesProvider).value ?? const <City>[];
    final cityName = {for (final c in cities) c.id: c.name};
    _cityId ??= cities.firstOrNull?.id;
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (canAct)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              DropdownButton<String>(
                value: _cityId,
                items: [for (final c in cities) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: (v) => setState(() => _cityId = v),
              ),
              DropdownButton<String>(
                value: _kind,
                items: [
                  DropdownMenuItem(value: 'detect', child: Text(s.detectRun)),
                  DropdownMenuItem(value: 'fires', child: Text(s.firesRun)),
                ],
                onChanged: (v) => setState(() => _kind = v ?? 'detect'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: Text(s.queueRun),
                onPressed: _cityId == null
                    ? null
                    : () async {
                        final ok = await guarded(context, () => ref.read(actionsProvider).queueRun(_cityId!, _kind),
                            success: s.runQueued);
                        if (ok) ref.invalidate(runsProvider);
                      },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.fact_check),
                label: Text(s.verifyAll),
                onPressed: () async {
                  try {
                    final n = await ref.read(actionsProvider).verifyAll();
                    ref.invalidate(sitesProvider);
                    if (context.mounted) toast(context, '$n ${s.verifiedCount}');
                  } catch (e) {
                    if (context.mounted) toast(context, '$e');
                  }
                },
              ),
            ]),
          ),
        ),
      AsyncView(ref.watch(runsProvider), onRetry: () => ref.invalidate(runsProvider), builder: (runs) {
        if (runs.isEmpty) return const EmptyNote();
        return Column(children: [
          for (final r in runs)
            Card(
              child: ListTile(
                leading: Icon(r.kind == 'fires' ? Icons.local_fire_department : Icons.satellite_alt),
                title: Text('${cityName[r.cityId] ?? r.cityId ?? '-'} · ${r.kind}'),
                subtitle: Text([
                  fmtDateTime(r.queuedAt),
                  if (r.scenesProcessed > 0) '${r.scenesProcessed} scenes',
                  if (r.sitesNew > 0 || r.sitesUpdated > 0) '+${r.sitesNew} new, ${r.sitesUpdated} updated',
                  if (r.error != null) r.error!,
                ].join(' · ')),
                trailing: StatusChip(r.status),
              ),
            ),
        ]);
      }),
    ]);
  }
}

class _UsersTab extends ConsumerWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final me = ref.watch(userIdProvider);
    return AsyncView(ref.watch(profilesProvider), onRetry: () => ref.invalidate(profilesProvider), builder: (list) {
      return ListView(padding: const EdgeInsets.all(12), children: [
        for (final p in list)
          Card(
            child: ListTile(
              title: Text(p.fullName ?? p.email ?? p.userId),
              subtitle: Text(p.email ?? ''),
              trailing: DropdownButton<String>(
                value: p.role,
                items: [
                  for (final r in ['citizen', 'officer', 'board', 'admin'])
                    DropdownMenuItem(value: r, child: Text(s.roleName(r))),
                ],
                onChanged: p.userId == me
                    ? null
                    : (role) async {
                        if (role == null) return;
                        final ok = await guarded(context, () => ref.read(repoProvider).setUserRole(p.userId, role),
                            success: s.saved);
                        if (ok) ref.invalidate(profilesProvider);
                      },
              ),
            ),
          ),
      ]);
    });
  }
}
