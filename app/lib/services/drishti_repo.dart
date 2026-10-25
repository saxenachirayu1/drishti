import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/action.dart';
import '../models/place.dart';
import '../models/site.dart';

/// Every Supabase read and write the app makes. Screens never name tables.
class DrishtiRepo {
  DrishtiRepo(this.db);

  final SupabaseClient db;

  User? get user => db.auth.currentUser;
  String? get accessToken => db.auth.currentSession?.accessToken;

  List<T> _rows<T>(List<Map<String, dynamic>> rows, T Function(Map<String, dynamic>) f) =>
      [for (final r in rows) f(r)];

  // --- auth ----------------------------------------------------------------

  Future<void> signIn(String email, String password) =>
      db.auth.signInWithPassword(email: email, password: password);

  Future<AuthResponse> signUp(String email, String password, String fullName) =>
      db.auth.signUp(email: email, password: password, data: {'full_name': fullName});

  Future<void> signOut() => db.auth.signOut();

  // --- places and sites (public) --------------------------------------------

  Future<List<City>> cities() async =>
      _rows(await db.from('city_list').select().order('name', ascending: true), City.fromMap);

  Future<List<Ward>> wards({String? cityId}) async {
    var q = db.from('ward_map').select();
    if (cityId != null) q = q.eq('city_id', cityId);
    return _rows(await q.order('ward_no', ascending: true), Ward.fromMap);
  }

  Future<List<Site>> sites({String? cityId}) async {
    var q = db.from('site_map').select();
    if (cityId != null) q = q.eq('city_id', cityId);
    return _rows(await q.order('last_seen', ascending: false), Site.fromMap);
  }

  Future<Site?> site(String id) async {
    final row = await db.from('site_map').select().eq('id', id).maybeSingle();
    return row == null ? null : Site.fromMap(row);
  }

  Future<List<Detection>> timeline(String siteId) async => _rows(
      await db.from('detection_timeline').select().eq('site_id', siteId).order('detected_on', ascending: true),
      Detection.fromMap);

  Future<List<FireEvent>> fires({String? siteId, int limit = 500}) async {
    var q = db.from('fire_map').select();
    if (siteId != null) q = q.eq('site_id', siteId);
    return _rows(await q.order('detected_at', ascending: false).limit(limit), FireEvent.fromMap);
  }

  Future<List<CityScore>> leaderboard() async =>
      _rows(await db.from('city_leaderboard').select().order('rank', ascending: true), CityScore.fromMap);

  Future<List<Verification>> verifications(String siteId) async => _rows(
      await db.from('verifications').select().eq('site_id', siteId).order('checked_at', ascending: false),
      Verification.fromMap);

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

  Future<void> updateMyProfile({String? fullName, String? language}) async {
    final uid = user?.id;
    if (uid == null) return;
    await db.from('profiles').update({
      'full_name': ?fullName,
      'language': ?language,
    }).eq('user_id', uid);
  }

  Future<List<Profile>> profiles() async =>
      _rows(await db.from('profiles').select().order('email', ascending: true), Profile.fromMap);

  Future<void> setUserRole(String userId, String role) =>
      db.rpc('set_user_role', params: {'target': userId, 'new_role': role});

  // --- citizen reports -------------------------------------------------------

  /// Uploads to `report-photos/<user id>/<time>.<ext>` and returns the public URL.
  Future<String> uploadReportPhoto(Uint8List bytes, {String ext = 'jpg'}) async {
    final uid = user?.id;
    if (uid == null) throw StateError('Sign in first');
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final type = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
    final bucket = db.storage.from('report-photos');
    await bucket.uploadBinary(path, bytes, fileOptions: FileOptions(contentType: type));
    return bucket.getPublicUrl(path);
  }

  /// Files the report and matches it to a site within 150 m.
  /// Returns {id, status: matched|flagged_for_review, site_id, nearest_site_id, distance_m}.
  Future<Map<String, dynamic>> submitReport({
    required double lat,
    required double lng,
    String? note,
    String? photoUrl,
  }) async {
    final res = await db.rpc('submit_report',
        params: {'lng': lng, 'lat': lat, 'note': note, 'photo_url': photoUrl});
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<CitizenReport>> myReports() async {
    final uid = user?.id;
    if (uid == null) return const [];
    return _rows(
        await db.from('report_map').select().eq('user_id', uid).order('created_at', ascending: false),
        CitizenReport.fromMap);
  }

  Future<List<CitizenReport>> allReports({String? status}) async {
    var q = db.from('report_map').select();
    if (status != null) q = q.eq('status', status);
    return _rows(await q.order('created_at', ascending: false), CitizenReport.fromMap);
  }

  // --- officer actions -------------------------------------------------------

  Future<Complaint> insertComplaint({
    required String siteId,
    required String text,
    required String language,
  }) async =>
      Complaint.fromMap(await db
          .from('complaints')
          .insert({'site_id': siteId, 'draft_text': text, 'language': language})
          .select()
          .single());

  Future<Complaint> updateComplaint(String id, Map<String, dynamic> fields) async =>
      Complaint.fromMap(await db.from('complaints').update(fields).eq('id', id).select().single());

  Future<void> updateSite(String id, Map<String, dynamic> fields) =>
      db.from('sites').update(fields).eq('id', id);

  Future<void> reviewReport(String id, {required String status, String? linkedSiteId}) =>
      db.from('citizen_reports').update({'status': status, 'linked_site_id': linkedSiteId}).eq('id', id);

  Future<void> addVerification({
    required String siteId,
    required String result,
    String? complaintId,
    String? evidenceDetectionId,
  }) =>
      db.from('verifications').insert({
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
      PipelineRun.fromMap);

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
