import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Future<void> _setHindi(bool hindi) async {
    ref.read(hindiProvider.notifier).set(hindi);
    if (ref.read(userIdProvider) != null) {
      await guarded(context, () => ref.read(repoProvider).updateMyProfile(language: hindi ? 'Hindi' : 'English'));
      ref.invalidate(profileProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final hindi = ref.watch(hindiProvider);
    final usesApi = ref.watch(actionsProvider).usesApi;
    final signedIn = ref.watch(userIdProvider) != null;

    final language = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(child: Text(s.language)),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('English')),
              ButtonSegment(value: true, label: Text('हिन्दी')),
            ],
            selected: {hindi},
            onSelectionChanged: (v) => _setHindi(v.first),
          ),
        ]),
      ),
    );

    final mode = Padding(
      padding: const EdgeInsets.all(8),
      child: Row(children: [
        Icon(usesApi ? Icons.cloud_done : Icons.storage, size: 16),
        const SizedBox(width: 6),
        Expanded(child: Text(usesApi ? s.apiMode : s.localMode, style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(s.appName, style: Theme.of(context).textTheme.headlineMedium),
          Text(s.tagline),
          const SizedBox(height: 16),
          language,
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
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    InfoRow(s.email, p.email ?? '-'),
                    InfoRow(s.role, s.roleName(p.role)),
                    TextField(
                      controller: _name,
                      decoration: InputDecoration(
                        labelText: s.fullName,
                        suffixIcon: IconButton(
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
          mode,
        ]),
      ),
    );
  }
}
