import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/action.dart';
import '../models/place.dart';
import '../models/site.dart';

/// Where the last good copy of the map data is kept, so the map still opens
/// offline (A-24). The app uses shared_preferences; tests pass none.
abstract class RowCache {
  String? read(String key);
  Future<void> write(String key, String value);
}

/// Every Supabase read and write the app makes. Screens never name tables.
class DrishtiRepo {
  DrishtiRepo(this.db, {this.cache});

  final SupabaseClient db;
  final RowCache? cache;

  /// True while the map data on screen came from the offline cache.
  final offline = ValueNotifier<bool>(false);

  User? get user => db.auth.currentUser;
  String? get accessToken => db.auth.currentSession?.accessToken;

  List<T> _rows<T>(List<Map<String, dynamic>> rows, T Function(Map<String, dynamic>) f) => [for (final r in rows) f(r)];

  /// Runs a public read; on success keeps a copy, on a network failure returns the copy.
  Future<List<Map<String, dynamic>>> _cached(String key, Future<List<Map<String, dynamic>>> Function() fetch) async {
    try {
      final rows = await fetch().timeout(const Duration(seconds: 12));
      offline.value = false;
      await cache?.write(key, jsonEncode(rows));
      return rows;
    } on PostgrestException {
      rethrow; // the server answered: a real error, not a lost connection
    } catch (_) {
      final saved = cache?.read(key);
      if (saved == null) rethrow;
      offline.value = true;
      return [for (final r in jsonDecode(saved) as List) Map<String, dynamic>.from(r as Map)];
    }
  }

  // --- auth (A-08) ----------------------------------------------------------

  /// Emails a 6-digit code (and creates the account the first time).
  Future<void> sendCode(String email) => db.auth.signInWithOtp(email: email, shouldCreateUser: true);

  Future<void> verifyCode(String email, String code) =>
      db.auth.verifyOTP(email: email, token: code, type: OtpType.email);

  Future<void> signIn(String email, String password) => db.auth.signInWithPassword(email: email, password: password);

  Future<AuthResponse> signUp(String email, String password, String fullName) =>
      db.auth.signUp(email: email, password: password, data: {'full_name': fullName});

  Future<void> signOut() => db.auth.signOut();

  // --- places and sites (public) --------------------------------------------

  Future<List<City>> cities() async =>
      _rows(await _cached('cities', () => db.from('city_list').select().order('name', ascending: true)), City.fromMap);

  Future<List<Ward>> wards({String? cityId}) async {
    var q = db.from('ward_map').select();
    if (cityId != null) q = q.eq('city_id', cityId);
    return _rows(await _cached('wards:${cityId ?? 'all'}', () => q.order('ward_no', ascending: true)), Ward.fromMap);
  }

  Future<List<Site>> sites({String? cityId}) async {
    var q = db.from('site_map').select();
    if (cityId != null) q = q.eq('city_id', cityId);
    return _rows(await _cached('sites:${cityId ?? 'all'}', () => q.order('last_seen', ascending: false)), Site.fromMap);
  }

  Future<Site?> site(String id) async {
    final row = await db.from('site_map').select().eq('id', id).maybeSingle();
    return row == null ? null : Site.fromMap(row);
  }

  Future<List<Detection>> timeline(String siteId) async => _rows(
    await db.from('detection_timeline').select().eq('site_id', siteId).order('detected_on', ascending: true),
    Detection.fromMap,
  );

  Future<List<FireEvent>> fires({String? siteId, int limit = 500}) async {
    var q = db.from('fire_map').select();
    if (siteId != null) q = q.eq('site_id', siteId);
    final key = 'fires:${siteId ?? 'all'}';
    return _rows(await _cached(key, () => q.order('detected_at', ascending: false).limit(limit)), FireEvent.fromMap);
  }

  Future<List<CityScore>> leaderboard() async => _rows(
    await _cached('leaderboard', () => db.from('city_leaderboard').select().order('rank', ascending: true)),
    CityScore.fromMap,
  );

  /// Every month's score for one city, oldest first (A-20 trend).
  Future<List<(String, int)>> scoreHistory(String cityId) async {
    final rows = await _cached(
      'scores:$cityId',
      () => db.from('city_scores').select('period, score').eq('city_id', cityId).order('period', ascending: true),
    );
    return [for (final r in rows) (r['period'] as String, (r['score'] as num?)?.round() ?? 0)];
  }

  Future<List<Verification>> verifications(String siteId) async => _rows(
    await db.from('verifications').select().eq('site_id', siteId).order('checked_at', ascending: false),
    Verification.fromMap,
  );

  /// The public sees sent and closed complaints; staff also see drafts.
  Future<List<Complaint>> complaints({String? siteId, String? status}) async {
    var q = db.from('complaints').select();
    if (siteId != null) q = q.eq('site_id', siteId);
    if (status != null) q = q.eq('status', status);
    return _rows(await q.order('created_at', ascending: false), Complaint.fromMap);
  }

  Future<Complaint?> complaint(String id) async {
    final row = await db.from('complaints').select().eq('id', id).maybeSingle();
    return row == null ? null : Complaint.fromMap(row);
  }

  // --- profile ---------------------------------------------------------------

  Future<Profile?> myProfile() async {
    final uid = user?.id;
    if (uid == null) return null;
    final row = await db.from('profiles').select().eq('user_id', uid).maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  Future<void> updateMyProfile({String? fullName, String? language, String? cityId}) async {
    final uid = user?.id;
    if (uid == null) return;
    await db
        .from('profiles')
        .update({'full_name': ?fullName, 'language': ?language, 'city_id': ?cityId})
        .eq('user_id', uid);
  }

  Future<List<Profile>> profiles() async =>
      _rows(await db.from('profiles').select().order('email', ascending: true), Profile.fromMap);

  Future<void> setUserRole(String userId, String role) =>
      db.rpc('set_user_role', params: {'target': userId, 'new_role': role});

  /// Admins only: role and home city together (A-18: officers see their city).
  Future<void> setUserAccess(String userId, String role, String? cityId) =>
      db.rpc('set_user_access', params: {'target': userId, 'new_role': role, 'new_city': cityId});

  // --- citizen reports -------------------------------------------------------

  /// Re-encodes the photo as JPEG without EXIF (N-12: the location is kept in
  /// the report itself, never in the file), then uploads it to the private
  /// `reports` bucket under the reporter's folder. Returns the storage path.
  Future<String> uploadReportPhoto(Uint8List bytes) async {
    final uid = user?.id;
    if (uid == null) throw StateError('Sign in first');
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw ArgumentError('Not an image');
    final upright = img.bakeOrientation(decoded)..exif = img.ExifData();
    final clean = Uint8List.fromList(img.encodeJpg(upright, quality: 85));
    final name = '$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await db.storage
        .from('reports')
        .uploadBinary(name, clean, fileOptions: const FileOptions(contentType: 'image/jpeg'));
    return 'reports/$name';
  }

  /// A viewable URL for a report photo: a short-lived signed URL for the
  /// private bucket, or the URL itself for older public uploads.
  Future<String?> photoUrl(String? stored) async {
    if (stored == null) return null;
    if (stored.startsWith('http')) return stored;
    final slash = stored.indexOf('/');
    return db.storage.from(stored.substring(0, slash)).createSignedUrl(stored.substring(slash + 1), 3600);
  }

  /// Files the report and matches it to a site within 150 m.
  /// Returns {id, status: matched|flagged_for_review, site_id, nearest_site_id, distance_m}.
  Future<Map<String, dynamic>> submitReport({
    required double lat,
    required double lng,
    String? note,
    String? photoUrl,
  }) async {
    final res = await db.rpc('submit_report', params: {'lng': lng, 'lat': lat, 'note': note, 'photo_url': photoUrl});
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<CitizenReport>> myReports() async {
    final uid = user?.id;
    if (uid == null) return const [];
    return _rows(
      await db.from('report_map').select().eq('user_id', uid).order('created_at', ascending: false),
      CitizenReport.fromMap,
    );
  }

  Future<List<CitizenReport>> allReports({String? status, String? siteId}) async {
    var q = db.from('report_map').select();
    if (status != null) q = q.eq('status', status);
    if (siteId != null) q = q.eq('linked_site_id', siteId);
    return _rows(await q.order('created_at', ascending: false), CitizenReport.fromMap);
  }

  // --- officer actions -------------------------------------------------------

  Future<Complaint> insertComplaint({required String siteId, required String text, required String language}) async =>
      Complaint.fromMap(
        await db
            .from('complaints')
            .insert({'site_id': siteId, 'draft_text': text, 'language': language})
            .select()
            .single(),
      );

  Future<Complaint> updateComplaint(String id, Map<String, dynamic> fields) async =>
      Complaint.fromMap(await db.from('complaints').update(fields).eq('id', id).select().single());

  Future<void> updateSite(String id, Map<String, dynamic> fields) => db.from('sites').update(fields).eq('id', id);

  /// Sites an admin has not reviewed yet, newest first (A-22).
  Future<List<Site>> unreviewedSites() async => _rows(
    await db
        .from('site_map')
        .select()
        .isFilter('reviewed_at', null)
        .neq('status', 'dismissed')
        .order('first_seen', ascending: false),
    Site.fromMap,
  );

  Future<void> markReviewed(String siteId) => db
      .from('sites')
      .update({'reviewed_at': DateTime.now().toUtc().toIso8601String(), 'reviewed_by': user?.id})
      .eq('id', siteId);

  Future<void> reviewReport(String id, {required String status, String? linkedSiteId}) =>
      db.from('citizen_reports').update({'status': status, 'linked_site_id': linkedSiteId}).eq('id', id);

  Future<void> addVerification({
    required String siteId,
    required String result,
    String? complaintId,
    String? evidenceDetectionId,
  }) => db.from('verifications').insert({
    'site_id': siteId,
    'result': result,
    'complaint_id': complaintId,
    'evidence_detection_id': evidenceDetectionId,
  });

  Future<void> refreshScore(String cityId) => db.rpc('refresh_city_score', params: {'p_city_id': cityId});

  /// B's worker (`drishti-pipeline worker`) picks up queued rows.
  Future<void> queueRun({required String cityId, required String kind, Map<String, dynamic>? params}) =>
      db.from('pipeline_runs').insert({'city_id': cityId, 'kind': kind, 'params': params ?? {}});

  Future<List<PipelineRun>> runs() async => _rows(
    await db.from('pipeline_runs').select().order('queued_at', ascending: false).limit(50),
    PipelineRun.fromMap,
  );

  Future<void> audit(String action, String entity, String entityId, [Map<String, dynamic>? details]) async {
    final uid = user?.id;
    if (uid == null) return;
    await db.from('audit_log').insert({
      'actor': uid,
      'action': action,
      'entity': entity,
      'entity_id': entityId,
      'details': details ?? {},
    });
  }
}
