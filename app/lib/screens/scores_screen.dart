import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/place.dart';
import '../providers.dart';
import '../widgets/common.dart';

/// The public "cleanliness from space" leaderboard.
class ScoresScreen extends ConsumerWidget {
  const ScoresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final canAct = ref.watch(profileProvider).value?.canAct ?? false;
    final sites = ref.watch(sitesProvider).value ?? const [];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(leaderboardProvider),
          child: ListView(padding: const EdgeInsets.all(12), children: [
            Text(s.leaderboard, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(s.scoreHint, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            AsyncView(ref.watch(leaderboardProvider), onRetry: () => ref.invalidate(leaderboardProvider),
                builder: (rows) {
              if (rows.isEmpty) return const EmptyNote();
              return Column(children: [
                for (final row in rows)
                  _ScoreCard(
                    score: row,
                    liveActive: sites.where((x) => x.cityId == row.cityId && x.status == 'active').length,
                    canAct: canAct,
                  ),
              ]);
            }),
          ]),
        ),
      ),
    );
  }
}

class _ScoreCard extends ConsumerWidget {
  const _ScoreCard({required this.score, required this.liveActive, required this.canAct});
  final CityScore score;
  final int liveActive;
  final bool canAct;

  Color _color(int v) => v >= 75 ? Colors.green : (v >= 50 ? Colors.orange : Colors.red);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final parts = [
      (s.partActive, score.parts['active']),
      (s.partBurn, score.parts['burn']),
      (s.partClear, score.parts['clear_time']),
      (s.partVerified, score.parts['verified']),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(child: Text('#${score.rank}')),
        title: Text(score.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${score.state ?? ''} · ${score.period}'),
        trailing: Text('${score.score}',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _color(score.score))),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (final (label, v) in parts)
            if (v != null) MeterBar(label: label, fraction: v, trailing: '${(v * 100).round()}%'),
          const SizedBox(height: 8),
          InfoRow(s.activeSites, '${score.activeSites} (${s.map.toLowerCase()}: $liveActive)'),
          InfoRow(s.burnEvents, '${score.burnEvents}'),
          if (score.medianDaysToClear != null) InfoRow(s.daysToClear, score.medianDaysToClear!.toStringAsFixed(0)),
          if (score.pctVerifiedCleared != null)
            InfoRow(s.verifiedCleared, '${(score.pctVerifiedCleared! * 100).round()}%'),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: Text(s.trend, style: Theme.of(context).textTheme.labelLarge)),
          const SizedBox(height: 4),
          AsyncView(ref.watch(scoreHistoryProvider(score.cityId)), builder: (months) => _Trend(months: months)),
          if (canAct)
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: Text(s.recompute),
                onPressed: () async {
                  final ok = await guarded(context, () => ref.read(actionsProvider).refreshScore(score.cityId));
                  if (ok) ref.invalidate(leaderboardProvider);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// One bar per month, labelled with the score (A-20).
class _Trend extends StatelessWidget {
  const _Trend({required this.months});
  final List<(String, int)> months;

  @override
  Widget build(BuildContext context) {
    final shown = months.length > 12 ? months.sublist(months.length - 12) : months;
    return SizedBox(
      height: 110,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final (period, score) in shown)
          Expanded(
            child: Semantics(
              label: '$period: $score',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('$score', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Container(
                    height: 60 * score / 100,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: period == shown.last.$1 ? 1 : 0.45),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(period.length >= 7 ? period.substring(5) : period, style: const TextStyle(fontSize: 10)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
