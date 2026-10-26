import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'l10n/l10n.dart';
import 'models/action.dart';
import 'models/place.dart';
import 'models/site.dart';
import 'services/action_engine.dart';
import 'services/api_client.dart';
import 'services/drishti_repo.dart';

class PrefsCache implements RowCache {
  PrefsCache(this.prefs);
  final SharedPreferences prefs;
  @override
  String? read(String key) => prefs.getString('cache:$key');
  @override
  Future<void> write(String key, String value) => prefs.setString('cache:$key', value);
}

/// Set in main() once shared_preferences has loaded.
final prefsProvider = Provider<SharedPreferences?>((ref) => null);

final repoProvider = Provider<DrishtiRepo>((ref) {
  final prefs = ref.watch(prefsProvider);
  return DrishtiRepo(Supabase.instance.client, cache: prefs == null ? null : PrefsCache(prefs));
});

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

// --- language (A-10) ----------------------------------------------------------------

class LocaleNotifier extends Notifier<String> {
  @override
  String build() => 'en';
  void set(String code) => state = code;
}

/// The UI language code ('en', 'hi', ... one per ARB file).
final localeProvider = NotifierProvider<LocaleNotifier, String>(LocaleNotifier.new);

final hindiProvider = Provider<bool>((ref) => ref.watch(localeProvider) == 'hi');

final stringsProvider = Provider<S>((ref) => stringsFor(ref.watch(localeProvider)));

// --- cross-screen requests ------------------------------------------------------------

class ValueNotifierOf<T> extends Notifier<T> {
  ValueNotifierOf(this._initial);
  final T _initial;
  @override
  T build() => _initial;
  void set(T value) => state = value;
}

/// A tab another screen wants opened ('map', 'complaints', ...). The shell clears it.
final tabRequestProvider = NotifierProvider<ValueNotifierOf<String?>, String?>(() => ValueNotifierOf(null));

/// Site ids the assistant asked the map to highlight (A-21).
final highlightProvider =
    NotifierProvider<ValueNotifierOf<List<String>>, List<String>>(() => ValueNotifierOf(const []));

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
    FutureProvider.family<List<Detection>, String>((ref, id) => ref.watch(actionsProvider).timeline(id));

final siteFiresProvider =
    FutureProvider.family<List<FireEvent>, String>((ref, id) => ref.watch(repoProvider).fires(siteId: id));

final siteComplaintsProvider = FutureProvider.family<List<Complaint>, String>((ref, id) {
  ref.watch(userIdProvider);
  return ref.watch(repoProvider).complaints(siteId: id);
});

final siteReportsProvider = FutureProvider.family<List<CitizenReport>, String>((ref, id) {
  ref.watch(userIdProvider);
  return ref.watch(repoProvider).allReports(siteId: id);
});

final complaintProvider = FutureProvider.family<Complaint?, String>((ref, id) {
  ref.watch(userIdProvider);
  return ref.watch(repoProvider).complaint(id);
});

final verificationsProvider =
    FutureProvider.family<List<Verification>, String>((ref, id) => ref.watch(repoProvider).verifications(id));

final leaderboardProvider = FutureProvider<List<CityScore>>((ref) => ref.watch(repoProvider).leaderboard());

final scoreHistoryProvider =
    FutureProvider.family<List<(String, int)>, String>((ref, id) => ref.watch(repoProvider).scoreHistory(id));

final photoUrlProvider =
    FutureProvider.family<String?, String>((ref, stored) => ref.watch(repoProvider).photoUrl(stored));

// --- citizen and officer lists -----------------------------------------------------------

final myReportsProvider = FutureProvider<List<CitizenReport>>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(repoProvider).myReports();
});

/// All reports, reloaded live when a citizen files one (A-19).
final allReportsProvider = FutureProvider<List<CitizenReport>>((ref) {
  ref.watch(userIdProvider);
  final repo = ref.watch(repoProvider);
  final channel = repo.db
      .channel('reports-${DateTime.now().microsecondsSinceEpoch}')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'citizen_reports',
        callback: (_) => ref.invalidateSelf(),
      )
      .subscribe();
  ref.onDispose(() => repo.db.removeChannel(channel));
  return repo.allReports();
});

final allComplaintsProvider = FutureProvider<List<Complaint>>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(repoProvider).complaints();
});

final unreviewedSitesProvider = FutureProvider<List<Site>>((ref) {
  ref.watch(sitesProvider);
  return ref.watch(repoProvider).unreviewedSites();
});

final runsProvider = FutureProvider<List<PipelineRun>>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(repoProvider).runs();
});

final profilesProvider = FutureProvider<List<Profile>>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(repoProvider).profiles();
});
