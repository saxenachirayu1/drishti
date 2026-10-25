import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'l10n/strings.dart';
import 'models/action.dart';
import 'models/place.dart';
import 'models/site.dart';
import 'services/action_engine.dart';
import 'services/api_client.dart';
import 'services/drishti_repo.dart';

final repoProvider = Provider<DrishtiRepo>((ref) => DrishtiRepo(Supabase.instance.client));

final apiProvider = Provider<DrishtiApi>((ref) {
  final repo = ref.watch(repoProvider);
  return DrishtiApi(AppConfig.apiBaseUrl, () => repo.accessToken);
});

final actionsProvider =
    Provider<ActionEngine>((ref) => ActionEngine(ref.watch(repoProvider), ref.watch(apiProvider)));

// --- auth and profile ----------------------------------------------------------

/// Emits on sign-in, sign-out and token refresh. Data providers that depend on
/// the viewer's role watch this so they reload with the right permissions.
final authProvider = StreamProvider<AuthState>((ref) => Supabase.instance.client.auth.onAuthStateChange);

final userIdProvider = Provider<String?>((ref) {
  ref.watch(authProvider);
  return ref.watch(repoProvider).user?.id;
});

final profileProvider = FutureProvider<Profile?>((ref) async {
  ref.watch(userIdProvider);
  return ref.watch(repoProvider).myProfile();
});

// --- language ---------------------------------------------------------------------

class HindiNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool hindi) => state = hindi;
}

final hindiProvider = NotifierProvider<HindiNotifier, bool>(HindiNotifier.new);

final stringsProvider = Provider<S>((ref) => S.of(ref.watch(hindiProvider)));

// --- map data -------------------------------------------------------------------------

final citiesProvider = FutureProvider<List<City>>((ref) => ref.watch(repoProvider).cities());

final wardsProvider = FutureProvider<List<Ward>>((ref) => ref.watch(repoProvider).wards());

/// All sites the viewer may see. Reloads live when B's pipeline or an officer
/// changes a site, and when the viewer signs in or out.
final sitesProvider = FutureProvider<List<Site>>((ref) async {
  ref.watch(userIdProvider);
  final repo = ref.watch(repoProvider);
  final channel = repo.db
      .channel('sites-${DateTime.now().microsecondsSinceEpoch}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'sites',
        callback: (_) => ref.invalidateSelf(),
      )
      .subscribe();
  ref.onDispose(() => repo.db.removeChannel(channel));
  return repo.sites();
});

final firesProvider = FutureProvider<List<FireEvent>>((ref) async {
  final repo = ref.watch(repoProvider);
  final channel = repo.db
      .channel('fires-${DateTime.now().microsecondsSinceEpoch}')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'fire_events',
        callback: (_) => ref.invalidateSelf(),
      )
      .subscribe();
  ref.onDispose(() => repo.db.removeChannel(channel));
  return repo.fires();
});

final siteProvider = FutureProvider.family<Site?, String>((ref, id) {
  ref.watch(sitesProvider);
  return ref.watch(repoProvider).site(id);
});

final timelineProvider =
    FutureProvider.family<List<Detection>, String>((ref, id) => ref.watch(repoProvider).timeline(id));

final siteFiresProvider =
    FutureProvider.family<List<FireEvent>, String>((ref, id) => ref.watch(repoProvider).fires(siteId: id));

final siteComplaintsProvider = FutureProvider.family<List<Complaint>, String>((ref, id) {
  ref.watch(userIdProvider);
  return ref.watch(repoProvider).complaints(siteId: id);
});

final complaintProvider = FutureProvider.family<Complaint?, String>((ref, id) {
  ref.watch(userIdProvider);
  return ref.watch(repoProvider).complaint(id);
});

final verificationsProvider =
    FutureProvider.family<List<Verification>, String>((ref, id) => ref.watch(repoProvider).verifications(id));

final leaderboardProvider = FutureProvider<List<CityScore>>((ref) => ref.watch(repoProvider).leaderboard());

// --- citizen and officer lists -----------------------------------------------------------

final myReportsProvider = FutureProvider<List<CitizenReport>>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(repoProvider).myReports();
});

final allReportsProvider = FutureProvider<List<CitizenReport>>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(repoProvider).allReports();
});

final allComplaintsProvider = FutureProvider<List<Complaint>>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(repoProvider).complaints();
});

final runsProvider = FutureProvider<List<PipelineRun>>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(repoProvider).runs();
});

final profilesProvider = FutureProvider<List<Profile>>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(repoProvider).profiles();
});
