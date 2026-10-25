import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/action.dart';
import '../models/place.dart';
import '../providers.dart';
import 'assistant_screen.dart';
import 'complaints_list_screen.dart';
import 'map_screen.dart';
import 'pipeline_screen.dart';
import 'profile_screen.dart';
import 'report_screen.dart';
import 'review_screen.dart';
import 'scores_screen.dart';
import '../widgets/common.dart';

/// Tabs by role (A-09): everyone gets Map, Scores, Report, Assistant and
/// Profile; officers and the board add Complaints; admins add Pipeline and
/// Review. Bottom navigation on phones, a side rail on the web dashboard.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  String _tab = 'map';
  String? _setupShownFor;

  void _firstTimeSetup(Profile p) {
    if (p.cityId != null || _setupShownFor == p.userId) return;
    _setupShownFor = p.userId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(context: context, barrierDismissible: false, builder: (_) => _SetupDialog(profile: p));
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final profile = ref.watch(profileProvider).value;
    final role = profile?.role ?? 'citizen';

    ref.listen(profileProvider, (_, next) {
      final p = next.value;
      if (p == null) return;
      ref.read(localeProvider.notifier).set(localeForLanguage(p.language));
      _firstTimeSetup(p);
    });
    ref.listen(tabRequestProvider, (_, tab) {
      if (tab == null) return;
      setState(() => _tab = tab);
      ref.read(tabRequestProvider.notifier).set(null);
    });

    final tabs = <(String, IconData, String, Widget)>[
      ('map', Icons.map_outlined, s.map, const MapScreen()),
      ('scores', Icons.leaderboard_outlined, s.scores, const ScoresScreen()),
      ('report', Icons.add_location_alt_outlined, s.report, const ReportScreen()),
      ('assistant', Icons.chat_outlined, s.assistant, const AssistantScreen()),
      if (role != 'citizen') ('complaints', Icons.description_outlined, s.complaints, const ComplaintsListScreen()),
      if (role == 'admin') ('pipeline', Icons.satellite_alt_outlined, s.pipeline, const PipelineScreen()),
      if (role == 'admin') ('review', Icons.fact_check_outlined, s.review, const ReviewScreen()),
      ('profile', Icons.person_outline, s.profile, const ProfileScreen()),
    ];
    final index = tabs.indexWhere((t) => t.$1 == _tab).clamp(0, tabs.length - 1);
    void select(int i) => setState(() => _tab = tabs[i].$1);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = IndexedStack(index: index, children: [for (final t in tabs) t.$4]);

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.satellite_alt),
          const SizedBox(width: 8),
          Text(s.appName),
          const SizedBox(width: 12),
          if (wide) Text(s.tagline, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: index,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: select,
                destinations: [for (final t in tabs) NavigationRailDestination(icon: Icon(t.$2), label: Text(t.$3))],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ])
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: select,
              labelBehavior: tabs.length > 5 ? NavigationDestinationLabelBehavior.onlyShowSelected : null,
              destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.$2), label: t.$3)],
            ),
    );
  }
}

/// First sign-in (A-08): pick a home city and language. Everyone starts as a
/// citizen; only an admin can grant officer, board or admin.
class _SetupDialog extends ConsumerStatefulWidget {
  const _SetupDialog({required this.profile});
  final Profile profile;

  @override
  ConsumerState<_SetupDialog> createState() => _SetupDialogState();
}

class _SetupDialogState extends ConsumerState<_SetupDialog> {
  String? _city;
  late String _locale = localeForLanguage(widget.profile.language);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final cities = ref.watch(citiesProvider).value ?? const <City>[];
    return AlertDialog(
      title: Text(s.welcome),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.setupHint),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _city,
          decoration: InputDecoration(labelText: s.homeCity),
          items: [for (final c in cities) DropdownMenuItem(value: c.id, child: Text(c.name))],
          onChanged: (v) => setState(() => _city = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _locale,
          decoration: InputDecoration(labelText: s.language),
          items: [
            for (final l in S.supportedLocales)
              DropdownMenuItem(value: l.languageCode, child: Text(stringsFor(l.languageCode).languageName)),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _locale = v);
            ref.read(localeProvider.notifier).set(v);
          },
        ),
        const SizedBox(height: 12),
        Text('${s.role}: ${s.roleName(widget.profile.role)}', style: Theme.of(context).textTheme.bodySmall),
      ]),
      actions: [
        FilledButton(
          onPressed: _city == null
              ? null
              : () async {
                  final ok = await guarded(
                      context,
                      () => ref
                          .read(repoProvider)
                          .updateMyProfile(cityId: _city, language: languageForLocale(_locale)));
                  if (!ok || !context.mounted) return;
                  ref.invalidate(profileProvider);
                  Navigator.pop(context);
                },
          child: Text(s.continueLabel),
        ),
      ],
    );
  }
}
