import 'package:latlong2/latlong.dart';

import 'parse.dart';

class Complaint {
  const Complaint({
    required this.id,
    required this.siteId,
    required this.draftText,
    required this.language,
    required this.status,
    this.wardId,
    this.pdfUrl,
    this.approvedBy,
    this.sentAt,
    this.closedAt,
    this.createdAt,
  });

  final String id;
  final String siteId;
  final String? wardId;
  final String draftText;
  final String language;
  final String? pdfUrl;
  final String status; // draft | approved | sent | closed
  final String? approvedBy;
  final DateTime? sentAt;
  final DateTime? closedAt;
  final DateTime? createdAt;

  factory Complaint.fromMap(Map<String, dynamic> m) => Complaint(
    id: m['id'] as String,
    siteId: m['site_id'] as String,
    wardId: m['ward_id'] as String?,
    draftText: m['draft_text'] as String? ?? '',
    language: m['language'] as String? ?? 'English',
    pdfUrl: m['pdf_url'] as String?,
    status: m['status'] as String? ?? 'draft',
    approvedBy: m['approved_by'] as String?,
    sentAt: asDate(m['sent_at']),
    closedAt: asDate(m['closed_at']),
    createdAt: asDate(m['created_at']),
  );
}

class Verification {
  const Verification({required this.id, required this.siteId, required this.result, this.complaintId, this.checkedAt});

  final String id;
  final String siteId;
  final String? complaintId;
  final String result; // still_present | shrinking | cleared
  final DateTime? checkedAt;

  factory Verification.fromMap(Map<String, dynamic> m) => Verification(
    id: m['id'] as String,
    siteId: m['site_id'] as String,
    complaintId: m['complaint_id'] as String?,
    result: m['result'] as String,
    checkedAt: asDate(m['checked_at']),
  );
}

/// A row of `report_map`.
class CitizenReport {
  const CitizenReport({
    required this.id,
    required this.status,
    this.userId,
    this.cityId,
    this.note,
    this.photoUrl,
    this.linkedSiteId,
    this.createdAt,
    this.lat,
    this.lng,
  });

  final String id;
  final String? userId;
  final String? cityId;
  final String? note;
  final String? photoUrl;
  final String status; // new | matched | rejected
  final String? linkedSiteId;
  final DateTime? createdAt;
  final double? lat;
  final double? lng;

  LatLng? get point => lat == null || lng == null ? null : LatLng(lat!, lng!);

  factory CitizenReport.fromMap(Map<String, dynamic> m) => CitizenReport(
    id: m['id'] as String,
    userId: m['user_id'] as String?,
    cityId: m['city_id'] as String?,
    note: m['note'] as String?,
    photoUrl: m['photo_url'] as String?,
    status: m['status'] as String? ?? 'new',
    linkedSiteId: m['linked_site_id'] as String?,
    createdAt: asDate(m['created_at']),
    lat: asDouble(m['lat']),
    lng: asDouble(m['lng']),
  );
}

class PipelineRun {
  const PipelineRun({
    required this.id,
    required this.kind,
    required this.status,
    this.cityId,
    this.queuedAt,
    this.startedAt,
    this.finishedAt,
    this.scenesProcessed = 0,
    this.sitesNew = 0,
    this.sitesUpdated = 0,
    this.error,
  });

  final String id;
  final String? cityId;
  final String kind;
  final String status; // queued | running | done | failed
  final DateTime? queuedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int scenesProcessed;
  final int sitesNew;
  final int sitesUpdated;
  final String? error;

  factory PipelineRun.fromMap(Map<String, dynamic> m) => PipelineRun(
    id: m['id'] as String,
    cityId: m['city_id'] as String?,
    kind: m['kind'] as String? ?? 'detect',
    status: m['status'] as String? ?? 'queued',
    queuedAt: asDate(m['queued_at']),
    startedAt: asDate(m['started_at']),
    finishedAt: asDate(m['finished_at']),
    scenesProcessed: asInt(m['scenes_processed']) ?? 0,
    sitesNew: asInt(m['sites_new']) ?? 0,
    sitesUpdated: asInt(m['sites_updated']) ?? 0,
    error: m['error'] as String?,
  );
}

class Profile {
  const Profile({
    required this.userId,
    required this.role,
    required this.language,
    this.email,
    this.fullName,
    this.cityId,
    this.wardId,
    this.department,
  });

  final String userId;
  final String? email;
  final String? fullName;
  final String role; // citizen | officer | board | admin
  final String? cityId;
  final String? wardId;
  final String language; // English | Hindi

  /// swm | pwd | cnd for department officers; the complaints console opens on it.
  final String? department;

  bool get isStaff => role == 'officer' || role == 'board' || role == 'admin';
  bool get canAct => role == 'officer' || role == 'admin';
  bool get isAdmin => role == 'admin';

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
    userId: m['user_id'] as String,
    email: m['email'] as String?,
    fullName: m['full_name'] as String?,
    role: m['role'] as String? ?? 'citizen',
    cityId: m['city_id'] as String?,
    wardId: m['ward_id'] as String?,
    language: m['language'] as String? ?? 'English',
    department: m['department'] as String?,
  );
}
