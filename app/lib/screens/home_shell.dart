import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'admin_screen.dart';
import 'assistant_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';
import 'report_screen.dart';
import 'scores_screen.dart';

/// Bottom navigation on phones, a side rail on the web dashboard.
/// The Officials tab appears only for officers, the board and admins.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final staff = ref.watch(profileProvider).value?.isStaff ?? false;

    // Use the signed-in user's saved language.
    ref.listen(profileProvider, (_, next) {
      final p = next.value;
      if (p != null) ref.read(hindiProvider.notifier).set(p.language == 'Hindi');
    });

    final tabs = <(IconData, String, Widget)>[
      (Icons.map_outlined, s.map, const MapScreen()),
      (Icons.leaderboard_outlined, s.scores, const ScoresScreen()),
      (Icons.add_location_alt_outlined, s.report, const ReportScreen()),
      (Icons.chat_outlined, s.assistant, const AssistantScreen()),
      if (staff) (Icons.admin_panel_settings_outlined, s.officials, const AdminScreen()),
      (Icons.person_outline, s.profile, const ProfileScreen()),
    ];
    final index = _index.clamp(0, tabs.length - 1);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = IndexedStack(index: index, children: [for (final t in tabs) t.$3]);

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
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: [
                  for (final t in tabs) NavigationRailDestination(icon: Icon(t.$1), label: Text(t.$2)),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ])
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.$1), label: t.$2)],
            ),
    );
  }
}
