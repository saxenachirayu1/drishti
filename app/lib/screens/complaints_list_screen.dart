import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/place.dart';
import '../models/site.dart';
import '../providers.dart';
import '../widgets/common.dart';
import 'complaint_screen.dart';

/// Officers' complaints list (A-18), filtered by status and ward. An officer
/// with a home city sees only that city's complaints.
class ComplaintsListScreen extends ConsumerStatefulWidget {
  const ComplaintsListScreen({super.key});

  @override
  ConsumerState<ComplaintsListScreen> createState() => _ComplaintsListScreenState();
}

class _ComplaintsListScreenState extends ConsumerState<ComplaintsListScreen> {
  String? _status;
  String? _wardId;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final profile = ref.watch(profileProvider).value;
    final sites = {for (final x in ref.watch(sitesProvider).value ?? const <Site>[]) x.id: x};
    final cityId = profile?.isAdmin ?? false ? null : profile?.cityId;
    final wards = (ref.watch(wardsProvider).value ?? const <Ward>[])
        .where((w) => cityId == null || w.cityId == cityId)
        .toList();

    return AsyncView(ref.watch(allComplaintsProvider), onRetry: () => ref.invalidate(allComplaintsProvider),
        builder: (all) {
      final list = all.where((c) {
        final site = sites[c.siteId];
        if (cityId != null && site?.cityId != cityId) return false;
        if (_status != null && c.status != _status) return false;
        if (_wardId != null && (c.wardId ?? site?.wardId) != _wardId) return false;
        return true;
      }).toList();
      return RefreshIndicator(
        onRefresh: () async => ref.invalidate(allComplaintsProvider),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ChoiceChip(label: Text(s.all), selected: _status == null, onSelected: (_) => setState(() => _status = null)),
            for (final st in ['draft', 'approved', 'sent', 'closed'])
              ChoiceChip(
                label: Text(s.status(st)),
                selected: _status == st,
                onSelected: (_) => setState(() => _status = st),
              ),
            DropdownButton<String?>(
              value: _wardId,
              hint: Text(s.anyWard),
              items: [
                DropdownMenuItem(value: null, child: Text(s.anyWard)),
                for (final w in wards) DropdownMenuItem(value: w.id, child: Text('${s.ward} ${w.wardNo ?? ''} · ${w.name ?? ''}')),
              ],
              onChanged: (v) => setState(() => _wardId = v),
            ),
          ]),
          const SizedBox(height: 8),
          if (list.isEmpty) const EmptyNote(),
          for (final c in list)
            Card(
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text('${s.site} ${c.siteId} · ${c.language}'),
                subtitle: Text(
                    '${s.ward} ${sites[c.siteId]?.wardNo ?? '-'} · ${fmtDateTime(c.sentAt ?? c.createdAt)}'),
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
