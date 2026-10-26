import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../complaints_providers.dart';
import '../models/place.dart';
import '../models/ticket.dart';
import '../providers.dart';
import '../theme/d_strings.dart';
import '../theme/drishti_theme.dart';
import '../widgets/common.dart';
import '../widgets/d_widgets.dart';
import 'scores_screen.dart';

/// What has changed on the ground, counted from the records. Every number
/// here comes from the database; the national figure is cited.
class ImpactScreen extends ConsumerStatefulWidget {
  const ImpactScreen({super.key, this.standalone = false});
  final bool standalone;

  @override
  ConsumerState<ImpactScreen> createState() => _ImpactScreenState();
}

class _ImpactScreenState extends ConsumerState<ImpactScreen> {
  String? _city;

  @override
  Widget build(BuildContext context) {
    final ds = ref.watch(dsProvider);
    final t = DText(ds.hindi);
    final cities = ref.watch(citiesProvider).value ?? const <City>[];
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final impact = ref.watch(impactProvider(_city));

    final body = ListView(
      padding: EdgeInsets.fromLTRB(narrow ? 20 : 32, 24, narrow ? 20 : 32, 40),
      children: [
        DPage(
          maxWidth: 1080,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(ds.impactTitle, style: t.head(narrow ? 30 : 40)),
              const SizedBox(height: 4),
              Text(ds.impactSub, style: t.body(15, color: DColors.body)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    key: const ValueKey('city-all'),
                    label: Text(ds.allCities),
                    selected: _city == null,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _city = null),
                  ),
                  for (final c in cities)
                    ChoiceChip(
                      key: ValueKey('city-${c.id}'),
                      label: Text(c.name),
                      selected: _city == c.id,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _city = c.id),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              AsyncView(
                impact,
                onRetry: () => ref.invalidate(impactProvider(_city)),
                builder: (Impact i) => _numbers(ds, t, i, narrow),
              ),
              const SizedBox(height: 40),
              _national(ds, t, narrow),
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerLeft,
                child: DSecondaryButton(
                  label: ds.cityScores,
                  height: 48,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(ds.cityScores)),
                        body: const ScoresScreen(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (!widget.standalone) return body;
    return Scaffold(
      appBar: AppBar(title: Text(ds.impactTitle)),
      body: body,
    );
  }

  Widget _numbers(DS ds, DText t, Impact i, bool narrow) {
    final fmt = NumberFormat.decimalPattern('en_IN');
    String hours(double? h) {
      if (h == null) return ds.none;
      if (h < 1) return '${(h * 60).round()} min';
      return h < 48 ? '${h.toStringAsFixed(h < 10 ? 1 : 0)} h' : '${(h / 24).toStringAsFixed(1)} d';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(ds.funnel, style: t.head(24)),
        const SizedBox(height: 12),
        DPanel(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _Funnel(
                steps: [
                  (ds.kSitesFound, i.sitesFound, DColors.signal),
                  (ds.kOpen, i.sitesOpen, DColors.ash),
                  (ds.kProven, i.sitesCleared, DColors.clean),
                ],
                hindi: ds.hindi,
              ),
              const Divider(height: 32),
              _Funnel(
                steps: [
                  (ds.kComplaints, i.complaints, DColors.ink),
                  (ds.kResolved, i.complaintsResolved, DColors.filed),
                  (ds.kProvenComplaints, i.complaintsProven, DColors.clean),
                ],
                hindi: ds.hindi,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, box) {
            final cols = box.maxWidth >= 760 ? 4 : 2;
            final w = (box.maxWidth - 12 * (cols - 1)) / cols;
            Widget tile(String label, String value, {Color color = DColors.ink}) => SizedBox(
              width: w,
              child: DPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: DText.mono(narrow ? 24 : 30, color: color, weight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Text(label, style: t.body(13, color: DColors.body)),
                  ],
                ),
              ),
            );
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                tile(
                  ds.kOnTime,
                  i.repliedOnTimePct == null ? ds.none : '${i.repliedOnTimePct}%',
                  color: (i.repliedOnTimePct ?? 0) >= 80 ? DColors.clean : DColors.ink,
                ),
                tile(ds.kMedian, hours(i.medianReplyHours)),
                tile(ds.kFires, fmt.format(i.fires30d), color: i.fires30d > 0 ? DColors.fire : DColors.ink),
                tile(ds.kArea, fmtArea(i.areaOpenM2)),
              ],
            );
          },
        ),
        const SizedBox(height: 28),
        Text(ds.byType, style: t.head(22)),
        const SizedBox(height: 12),
        DPanel(
          padding: const EdgeInsets.all(20),
          child: Builder(
            builder: (context) {
              final max = i.byCategory.values.fold<int>(0, (a, b) => a > b ? a : b);
              if (max == 0) return Text(ds.none, style: t.body(14, color: DColors.muted));
              return Column(
                children: [
                  for (final c in complaintTypes)
                    _Bar(
                      label: ds.typeName(c.id),
                      value: i.byCategory[c.id] ?? 0,
                      max: max,
                      color: c.id == 'burning' ? DColors.fire : DColors.ink,
                      hindi: ds.hindi,
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _national(DS ds, DText t, bool narrow) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(ds.nationalH, style: t.head(24)),
      const SizedBox(height: 12),
      DPanel(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ds.goal, style: t.head(narrow ? 20 : 24, height: 1.25)),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '1,048 ',
                    style: DText.mono(32, color: DColors.clean, weight: FontWeight.w500),
                  ),
                  TextSpan(
                    text: '/ 2,476',
                    style: DText.mono(16, color: DColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              label: ds.goalBarLabel,
              child: Container(
                height: 10,
                color: DColors.track,
                alignment: Alignment.centerLeft,
                child: const FractionallySizedBox(
                  widthFactor: 1048 / 2476,
                  heightFactor: 1,
                  child: ColoredBox(color: DColors.clean),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(ds.goalNote, style: t.body(14, color: DColors.body)),
            Text(ds.goalSource, style: t.body(12, color: DColors.muted)),
          ],
        ),
      ),
    ],
  );
}

/// Three counts left to right, each bar scaled to the first.
class _Funnel extends StatelessWidget {
  const _Funnel({required this.steps, required this.hindi});
  final List<(String, int, Color)> steps;
  final bool hindi;

  @override
  Widget build(BuildContext context) {
    final top = steps.first.$2;
    return Column(
      children: [for (final s in steps) _Bar(label: s.$1, value: s.$2, max: top, color: s.$3, hindi: hindi)],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.value, required this.max, required this.color, required this.hindi});
  final String label;
  final int value;
  final int max;
  final Color color;
  final bool hindi;

  @override
  Widget build(BuildContext context) {
    final f = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: Row(
          children: [
            SizedBox(width: 170, child: Text(label, style: DText(hindi).body(14))),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => Align(
                  alignment: Alignment.centerLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: f),
                    duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => Container(height: 14, width: box.maxWidth * v, color: color),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(
                NumberFormat.decimalPattern('en_IN').format(value),
                textAlign: TextAlign.right,
                style: DText.mono(14, weight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
