import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ticket.dart';

/// Complaints, tracking, areas and impact: everything the design D screens
/// read and write. An interface so the screens can be tested without a server.
abstract class ComplaintsApi {
  String? get userId;

  /// Emits when the user signs in or out.
  Stream<void> get authChanges;

  Future<List<AreaHit>> areaLookup(String query);
  Future<Impact> impact({String? cityId});
  Future<RoutePreview> routePreview({required double lat, required double lng, required String category});

  /// Files the complaint. Returns {id, ticket, status, site_id, department, ward_id, reply_due_at}.
  Future<Map<String, dynamic>> submit({
    required double lat,
    required double lng,
    required String category,
    String? note,
    Uint8List? photo,
  });

  /// The signed-in user's complaints, newest first.
  Future<List<Ticket>> mine();

  /// Public view of one complaint by its code; null if there is none.
  Future<Ticket?> track(String ticketCode);

  /// Full complaint with its timeline (reporter or staff).
  Future<Ticket?> ticket(String reportId);

  /// Every complaint the viewer may see (staff: all), optionally one department.
  Future<List<Ticket>> queue({String? department});

  Future<void> postUpdate(String reportId, String stage, {String? message, Uint8List? photo});
  Future<void> transfer(String reportId, String department);
  Future<void> reopen(String reportId, {String? reason});

  Future<Set<String>> follows();
  Future<void> setFollow(String localityId, bool on);

  /// A viewable URL for a stored photo path ('bucket/path'), or null.
  Future<String?> photoUrl(String? stored);

  /// Emits whenever this complaint's timeline changes.
  Stream<void> ticketChanges(String reportId);

  /// Emits whenever any complaint visible to the viewer is filed or updated.
  Stream<void> queueChanges();
}

/// Re-encodes a photo as JPEG without EXIF, so no location or device data
/// leaves the phone inside the file (N-12).
Uint8List cleanJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw ArgumentError('Not an image');
  final upright = img.bakeOrientation(decoded)..exif = img.ExifData();
  return Uint8List.fromList(img.encodeJpg(upright, quality: 85));
}

class SupabaseComplaints implements ComplaintsApi {
  SupabaseComplaints(this.db);
  final SupabaseClient db;

  @override
  String? get userId => db.auth.currentUser?.id;

  @override
  Stream<void> get authChanges => db.auth.onAuthStateChange.map((_) {});

  Map<String, dynamic> _map(Object? res) => Map<String, dynamic>.from(res as Map);

  @override
  Future<List<AreaHit>> areaLookup(String query) async {
    final rows = await db.rpc('area_lookup', params: {'q': query}) as List;
    return [for (final r in rows) AreaHit.fromMap(_map(r))];
  }

  @override
  Future<Impact> impact({String? cityId}) async =>
      Impact.fromMap(_map(await db.rpc('impact_summary', params: {'p_city_id': cityId})));

  @override
  Future<RoutePreview> routePreview({required double lat, required double lng, required String category}) async =>
      RoutePreview.fromMap(_map(await db.rpc('route_preview', params: {'lng': lng, 'lat': lat, 'category': category})));

  @override
  Future<Map<String, dynamic>> submit({
    required double lat,
    required double lng,
    required String category,
    String? note,
    Uint8List? photo,
  }) async {
    final uid = userId;
    if (uid == null) throw StateError('Sign in first');
    String? stored;
    if (photo != null) {
      final name = '$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await db.storage
          .from('reports')
          .uploadBinary(name, cleanJpeg(photo), fileOptions: const FileOptions(contentType: 'image/jpeg'));
      stored = 'reports/$name';
    }
    return _map(
      await db.rpc(
        'submit_report',
        params: {'lng': lng, 'lat': lat, 'note': note, 'photo_url': stored, 'category': category},
      ),
    );
  }

  @override
  Future<List<Ticket>> mine() async {
    final uid = userId;
    if (uid == null) return const [];
    final rows = await db.from('report_map').select().eq('user_id', uid).order('created_at', ascending: false);
    return [for (final r in rows) Ticket.fromMap(r)];
  }

  @override
  Future<Ticket?> track(String ticketCode) async {
    final res = await db.rpc('track_report', params: {'p_ticket': ticketCode});
    return res == null ? null : Ticket.fromMap(_map(res));
  }

  @override
  Future<Ticket?> ticket(String reportId) async {
    final row = await db.from('report_map').select().eq('id', reportId).maybeSingle();
    if (row == null) return null;
    final ups = await db.from('report_updates').select().eq('report_id', reportId).order('created_at', ascending: true);
    return Ticket.fromMap(row).withUpdates([for (final u in ups) TicketUpdate.fromMap(u)]);
  }

  @override
  Future<List<Ticket>> queue({String? department}) async {
    var q = db.from('report_map').select();
    if (department != null) q = q.eq('department', department);
    final rows = await q.order('created_at', ascending: false).limit(300);
    return [for (final r in rows) Ticket.fromMap(r)];
  }

  @override
  Future<void> postUpdate(String reportId, String stage, {String? message, Uint8List? photo}) async {
    String? path;
    if (photo != null) {
      final name = '$reportId/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await db.storage
          .from('report-updates')
          .uploadBinary(name, cleanJpeg(photo), fileOptions: const FileOptions(contentType: 'image/jpeg'));
      path = 'report-updates/$name';
    }
    await db.rpc(
      'post_report_update',
      params: {'p_report_id': reportId, 'p_stage': stage, 'p_message': message, 'p_photo_path': path},
    );
  }

  @override
  Future<void> transfer(String reportId, String department) =>
      db.rpc('transfer_report', params: {'p_report_id': reportId, 'p_department': department});

  @override
  Future<void> reopen(String reportId, {String? reason}) =>
      db.rpc('reopen_report', params: {'p_report_id': reportId, 'p_reason': reason});

  @override
  Future<Set<String>> follows() async {
    if (userId == null) return const {};
    final rows = await db.from('area_follows').select('locality_id');
    return {for (final r in rows) r['locality_id'] as String};
  }

  @override
  Future<void> setFollow(String localityId, bool on) async {
    final uid = userId;
    if (uid == null) throw StateError('Sign in first');
    if (on) {
      await db.from('area_follows').upsert({'user_id': uid, 'locality_id': localityId});
    } else {
      await db.from('area_follows').delete().eq('user_id', uid).eq('locality_id', localityId);
    }
  }

  @override
  Future<String?> photoUrl(String? stored) async {
    if (stored == null) return null;
    if (stored.startsWith('http')) return stored;
    final slash = stored.indexOf('/');
    if (slash < 0) return null;
    return db.storage.from(stored.substring(0, slash)).createSignedUrl(stored.substring(slash + 1), 3600);
  }

  Stream<void> _changes(String name, String table, {PostgresChangeFilter? filter}) {
    late final RealtimeChannel channel;
    final out = StreamController<void>.broadcast(onCancel: () => db.removeChannel(channel));
    channel = db
        .channel('$name-${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          filter: filter,
          callback: (_) => out.add(null),
        )
        .subscribe();
    return out.stream;
  }

  @override
  Stream<void> ticketChanges(String reportId) => _changes(
    'ticket',
    'report_updates',
    filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'report_id', value: reportId),
  );

  @override
  Stream<void> queueChanges() => _changes('queue', 'citizen_reports');
}
