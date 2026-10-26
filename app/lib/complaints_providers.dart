import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/ticket.dart';
import 'providers.dart';
import 'services/complaints_api.dart';
import 'theme/d_strings.dart';

/// Overridden in tests with a fake.
final complaintsApiProvider = Provider<ComplaintsApi>((ref) => SupabaseComplaints(Supabase.instance.client));

final _authTickProvider = StreamProvider<void>((ref) => ref.watch(complaintsApiProvider).authChanges);

/// The signed-in user's id, or null. Updates on sign-in and sign-out.
final meProvider = Provider<String?>((ref) {
  ref.watch(_authTickProvider);
  return ref.watch(complaintsApiProvider).userId;
});

final dsProvider = Provider<DS>((ref) => DS(ref.watch(hindiProvider)));

/// A place another screen wants the map to show (the home page area search).
final mapFocusProvider = NotifierProvider<ValueNotifierOf<LatLng?>, LatLng?>(() => ValueNotifierOf(null));

/// Ticks every minute so "due in" and "overdue" stay true without a reload.
final clockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(minutes: 1), (_) => DateTime.now());
});

/// The signed-in user's complaints, live.
final myTicketsProvider = StreamProvider.autoDispose<List<Ticket>>((ref) async* {
  final me = ref.watch(meProvider);
  final api = ref.watch(complaintsApiProvider);
  if (me == null) {
    yield const [];
    return;
  }
  yield await api.mine();
  await for (final _ in api.queueChanges()) {
    yield await api.mine();
  }
});

/// One complaint with its timeline, for its reporter or staff. Live.
final ticketProvider = StreamProvider.autoDispose.family<Ticket?, String>((ref, id) async* {
  ref.watch(meProvider);
  final api = ref.watch(complaintsApiProvider);
  yield await api.ticket(id);
  await for (final _ in api.ticketChanges(id)) {
    yield await api.ticket(id);
  }
});

/// Public tracking by code. Signed-out viewers cannot subscribe to the
/// timeline, so this refreshes every 30 seconds instead.
final trackProvider = StreamProvider.autoDispose.family<Ticket?, String>((ref, code) async* {
  final api = ref.watch(complaintsApiProvider);
  yield await api.track(code);
  await for (final _ in Stream.periodic(const Duration(seconds: 30))) {
    yield await api.track(code);
  }
});

/// The department queue (all departments when null). Live.
final queueProvider = StreamProvider.autoDispose.family<List<Ticket>, String?>((ref, dept) async* {
  ref.watch(meProvider);
  final api = ref.watch(complaintsApiProvider);
  yield await api.queue(department: dept);
  await for (final _ in api.queueChanges()) {
    yield await api.queue(department: dept);
  }
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
