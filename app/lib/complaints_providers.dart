import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'models/ticket.dart';
import 'providers.dart';
import 'services/complaints_api.dart';
import 'services/demo_complaints.dart';
import 'theme/d_strings.dart';

/// Overridden in tests with a fake.
final complaintsApiProvider = Provider<ComplaintsApi>(
  (ref) => AppConfig.demo ? DemoComplaints() : SupabaseComplaints(Supabase.instance.client),
);

final _authTickProvider = StreamProvider<void>((ref) => ref.watch(complaintsApiProvider).authChanges);

/// The signed-in user's id, or null. Updates on sign-in and sign-out.
final meProvider = Provider<String?>((ref) {
  ref.watch(_authTickProvider);
  return ref.watch(complaintsApiProvider).userId;
});

final dsProvider = Provider<DS>((ref) => DS(ref.watch(hindiProvider)));

/// A place another screen wants the map to show (the home page area search).
final mapFocusProvider = NotifierProvider<ValueNotifierOf<LatLng?>, LatLng?>(() => ValueNotifierOf(null));

/// A stream that loads once, then again on every [trigger] event (and every
/// [every], if given), and stops cleanly when the provider is disposed.
Stream<T> _refreshing<T>(Ref ref, Future<T> Function() load, {Stream<void>? trigger, Duration? every}) {
  final out = StreamController<T>();
  var closed = false;
  Future<void> run() async {
    try {
      final v = await load();
      if (!closed) out.add(v);
    } catch (e, st) {
      if (!closed) out.addError(e, st);
    }
  }

  run();
  final sub = trigger?.listen((_) => run());
  final timer = every == null ? null : Timer.periodic(every, (_) => run());
  ref.onDispose(() {
    closed = true;
    sub?.cancel();
    timer?.cancel();
    out.close();
  });
  return out.stream;
}

/// Ticks every minute so "due in" and "overdue" stay true without a reload.
final clockProvider = StreamProvider<DateTime>(
  (ref) => _refreshing(ref, () async => DateTime.now(), every: const Duration(minutes: 1)),
);

/// The signed-in user's complaints, live.
final myTicketsProvider = StreamProvider.autoDispose<List<Ticket>>((ref) {
  final me = ref.watch(meProvider);
  final api = ref.watch(complaintsApiProvider);
  if (me == null) return Stream.value(const <Ticket>[]);
  return _refreshing(ref, api.mine, trigger: api.queueChanges());
});

/// One complaint with its timeline, for its reporter or staff. Live.
final ticketProvider = StreamProvider.autoDispose.family<Ticket?, String>((ref, id) {
  ref.watch(meProvider);
  final api = ref.watch(complaintsApiProvider);
  return _refreshing(ref, () => api.ticket(id), trigger: api.ticketChanges(id));
});

/// Public tracking by code. Signed-out viewers cannot subscribe to the
/// timeline, so this refreshes every 30 seconds instead.
final trackProvider = StreamProvider.autoDispose.family<Ticket?, String>((ref, code) {
  final api = ref.watch(complaintsApiProvider);
  return _refreshing(ref, () => api.track(code), every: const Duration(seconds: 30));
});

/// The department queue (all departments when null). Live.
final queueProvider = StreamProvider.autoDispose.family<List<Ticket>, String?>((ref, dept) {
  ref.watch(meProvider);
  final api = ref.watch(complaintsApiProvider);
  return _refreshing(ref, () => api.queue(department: dept), trigger: api.queueChanges());
});

final impactProvider = FutureProvider.autoDispose.family<Impact, String?>(
  (ref, city) => ref.watch(complaintsApiProvider).impact(cityId: city),
);

final followsProvider = FutureProvider<Set<String>>((ref) {
  ref.watch(meProvider);
  return ref.watch(complaintsApiProvider).follows();
});

final routePreviewProvider = FutureProvider.autoDispose.family<RoutePreview, (double, double, String)>(
  (ref, k) => ref.watch(complaintsApiProvider).routePreview(lat: k.$1, lng: k.$2, category: k.$3),
);

final ticketPhotoProvider = FutureProvider.family<String?, String>(
  (ref, stored) => ref.watch(complaintsApiProvider).photoUrl(stored),
);
