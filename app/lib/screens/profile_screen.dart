import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../widgets/auth_form.dart';
import '../widgets/common.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _name = TextEditingController();
  String? _loadedFor;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// A-10: the choice is saved to the profile when signed in.
  Future<void> _setLanguage(String code) async {
    ref.read(localeProvider.notifier).set(code);
    if (ref.read(userIdProvider) != null) {
      await guarded(context, () => ref.read(repoProvider).updateMyProfile(language: languageForLocale(code)));
      ref.invalidate(profileProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final locale = ref.watch(localeProvider);
    final usesApi = ref.watch(actionsProvider).usesApi;
    final signedIn = ref.watch(userIdProvider) != null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(s.appName, style: Theme.of(context).textTheme.headlineMedium),
          Text(s.tagline),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(child: Text(s.language)),
                SegmentedButton<String>(
                  segments: [
                    for (final l in S.supportedLocales)
                      ButtonSegment(value: l.languageCode, label: Text(stringsFor(l.languageCode).languageName)),
                  ],
                  selected: {locale},
                  onSelectionChanged: (v) => _setLanguage(v.first),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          if (!signedIn)
            const Card(child: Padding(padding: EdgeInsets.all(16), child: AuthForm()))
          else
            AsyncView(ref.watch(profileProvider), onRetry: () => ref.invalidate(profileProvider), builder: (p) {
              if (p == null) return const EmptyNote();
              if (_loadedFor != p.userId) {
                _loadedFor = p.userId;
                _name.text = p.fullName ?? '';
              }
              final city = (ref.watch(citiesProvider).value ?? const []).where((c) => c.id == p.cityId).firstOrNull;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    InfoRow(s.email, p.email ?? '-'),
                    InfoRow(s.role, s.roleName(p.role)),
                    InfoRow(s.homeCity, city?.name ?? '-'),
                    TextField(
                      controller: _name,
                      decoration: InputDecoration(
                        labelText: s.fullName,
                        suffixIcon: IconButton(
                          tooltip: s.save,
                          icon: const Icon(Icons.save),
                          onPressed: () async {
                            final ok = await guarded(
                                context, () => ref.read(repoProvider).updateMyProfile(fullName: _name.text.trim()),
                                success: s.saved);
                            if (ok) ref.invalidate(profileProvider);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.logout),
                      label: Text(s.signOut),
                      onPressed: () => guarded(context, () => ref.read(repoProvider).signOut()),
                    ),
                  ]),
                ),
              );
            }),
          const SizedBox(height: 8),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.info_outline),
              title: Text(s.about),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                // N-24: data and model credits. Proper names, so not translated.
                Text('Contains modified Copernicus Sentinel data (2026), processed by Project Drishti.'),
                Text('Map data © OpenStreetMap contributors (ODbL).'),
                Text('Satellite basemap: Esri, Maxar, Earthstar Geographics.'),
                Text('Active fire data: NASA FIRMS (VIIRS), courtesy NASA LANCE.'),
                Text('Weather: Open-Meteo.com (CC BY 4.0).'),
                Text('Detection model: IBM-NASA Prithvi-EO, Apache 2.0 licence.'),
                Text('Language model: IBM Granite on watsonx.ai.'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Icon(usesApi ? Icons.cloud_done : Icons.storage, size: 16),
              const SizedBox(width: 6),
              Expanded(child: Text(usesApi ? s.apiMode : s.localMode, style: Theme.of(context).textTheme.bodySmall)),
            ]),
          ),
        ]),
      ),
    );
  }
}
