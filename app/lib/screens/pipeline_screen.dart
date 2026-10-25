import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/place.dart';
import '../providers.dart';
import '../widgets/common.dart';

/// Admins start pipeline runs and watch their status (A-22).
class PipelineScreen extends ConsumerStatefulWidget {
  const PipelineScreen({super.key});

  @override
  ConsumerState<PipelineScreen> createState() => _PipelineScreenState();
}

class _PipelineScreenState extends ConsumerState<PipelineScreen> {
  String? _cityId;
  String _kind = 'detect';

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final cities = ref.watch(citiesProvider).value ?? const <City>[];
    final cityName = {for (final c in cities) c.id: c.name};
    _cityId ??= cities.firstOrNull?.id;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(runsProvider),
      child: ListView(padding: const EdgeInsets.all(12), children: [
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
                  title: Text('${cityName[r.cityId] ?? r.cityId ?? '-'} · ${r.kind == 'fires' ? s.firesRun : s.detectRun}'),
                  subtitle: Text([
                    fmtDateTime(r.queuedAt),
                    if (r.scenesProcessed > 0) '${r.scenesProcessed} ${s.scenesLabel}',
                    if (r.sitesNew > 0 || r.sitesUpdated > 0)
                      '+${r.sitesNew} ${s.newLabel}, ${r.sitesUpdated} ${s.updatedLabel}',
                    ?r.error,
                  ].join(' · ')),
                  trailing: StatusChip(r.status),
                ),
              ),
          ]);
        }),
      ]),
    );
  }
}
