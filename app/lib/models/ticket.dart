import 'package:latlong2/latlong.dart';

import 'parse.dart';

/// The four complaint types. Mirrors `report_categories` in the database so
/// the form works before the table has loaded; the database is the authority.
class ComplaintType {
  const ComplaintType(this.id, this.replyHours, this.defaultDepartment);
  final String id;
  final int replyHours;
  final String defaultDepartment;
}

const complaintTypes = [
  ComplaintType('dump', 24, 'swm'),
  ComplaintType('burning', 2, 'swm'),
  ComplaintType('bin', 24, 'swm'),
  ComplaintType('debris', 48, 'cnd'),
];

ComplaintType complaintType(String id) =>
    complaintTypes.firstWhere((t) => t.id == id, orElse: () => complaintTypes.first);

/// The life of a complaint. `reopened` sits beside `received`: the clock restarts.
const stages = ['received', 'assigned', 'scheduled', 'in_progress', 'resolved', 'proven_clean'];

/// A complaint as the app lists it (a `report_map` row, or `track_report`).
class Ticket {
  const Ticket({
    required this.id,
    required this.stage,
    this.ticket,
    this.category = 'dump',
    this.department,
    this.userId,
    this.wardNo,
    this.wardName,
    this.locality,
    this.note,
    this.photoUrl,
    this.linkedSiteId,
    this.createdAt,
    this.replyDueAt,
    this.firstReplyAt,
    this.resolvedAt,
    this.updatedAt,
    this.lat,
    this.lng,
    this.updates = const [],
  });

  final String id;
  final String? ticket;
  final String category;
  final String stage;
  final String? department;
  final String? userId;
  final int? wardNo;
  final String? wardName;
  final String? locality;
  final String? note;
  final String? photoUrl;
  final String? linkedSiteId;
  final DateTime? createdAt;
  final DateTime? replyDueAt;
  final DateTime? firstReplyAt;
  final DateTime? resolvedAt;
  final DateTime? updatedAt;
  final double? lat;
  final double? lng;
  final List<TicketUpdate> updates;

  LatLng? get point => lat == null || lng == null ? null : LatLng(lat!, lng!);

  bool get isClosed => stage == 'resolved' || stage == 'proven_clean';

  factory Ticket.fromMap(Map<String, dynamic> m) => Ticket(
    id: m['id'] as String,
    ticket: m['ticket'] as String?,
    category: m['category'] as String? ?? 'dump',
    stage: m['stage'] as String? ?? 'received',
    department: m['department'] as String?,
    userId: m['user_id'] as String?,
    wardNo: asInt(m['ward_no']),
    wardName: m['ward_name'] as String?,
    locality: m['locality'] as String?,
    note: m['note'] as String?,
    photoUrl: m['photo_url'] as String?,
    linkedSiteId: m['linked_site_id'] as String?,
    createdAt: asDate(m['created_at']),
    replyDueAt: asDate(m['reply_due_at']),
    firstReplyAt: asDate(m['first_reply_at']),
    resolvedAt: asDate(m['resolved_at']),
    updatedAt: asDate(m['updated_at']),
    lat: asDouble(m['lat']),
    lng: asDouble(m['lng']),
    updates: [
      for (final u in (m['updates'] as List? ?? const [])) TicketUpdate.fromMap(Map<String, dynamic>.from(u as Map)),
    ],
  );

  Ticket withUpdates(List<TicketUpdate> list) => Ticket(
    id: id,
    ticket: ticket,
    category: category,
    stage: stage,
    department: department,
    userId: userId,
    wardNo: wardNo,
    wardName: wardName,
    locality: locality,
    note: note,
    photoUrl: photoUrl,
    linkedSiteId: linkedSiteId,
    createdAt: createdAt,
    replyDueAt: replyDueAt,
    firstReplyAt: firstReplyAt,
    resolvedAt: resolvedAt,
    updatedAt: updatedAt,
    lat: lat,
    lng: lng,
    updates: list,
  );
}

/// One entry on a complaint's timeline (`report_updates`).
class TicketUpdate {
  const TicketUpdate({
    required this.stage,
    required this.authorRole,
    this.id,
    this.message,
    this.photoPath,
    this.hasPhoto = false,
    this.createdAt,
  });

  final String? id;
  final String stage; // a stage, or 'note'
  final String authorRole; // system | department | citizen
  final String? message;
  final String? photoPath;
  final bool hasPhoto;
  final DateTime? createdAt;

  factory TicketUpdate.fromMap(Map<String, dynamic> m) => TicketUpdate(
    id: m['id'] as String?,
    stage: m['stage'] as String? ?? 'note',
    authorRole: m['author_role'] as String? ?? 'system',
    message: m['message'] as String?,
    photoPath: m['photo_path'] as String?,
    hasPhoto: m['has_photo'] as bool? ?? m['photo_path'] != null,
    createdAt: asDate(m['created_at']),
  );
}

/// Where a complaint would go, shown before it is sent (`route_preview`).
class RoutePreview {
  const RoutePreview({required this.department, this.onPwdRoad = false, this.replyHours, this.wardNo, this.wardName});
  final String department;
  final bool onPwdRoad;
  final int? replyHours;
  final int? wardNo;
  final String? wardName;

  factory RoutePreview.fromMap(Map<String, dynamic> m) => RoutePreview(
    department: m['department'] as String? ?? 'swm',
    onPwdRoad: m['on_pwd_road'] as bool? ?? false,
    replyHours: asInt(m['reply_hours']),
    wardNo: asInt(m['ward_no']),
    wardName: m['ward_name'] as String?,
  );
}

/// A home page search hit (`area_lookup`).
class AreaHit {
  const AreaHit({
    required this.id,
    required this.name,
    required this.cityName,
    this.nameHi,
    this.pincode,
    this.cityId,
    this.lat,
    this.lng,
    this.openSites = 0,
    this.lastPass,
    this.nextPass,
  });

  final String id;
  final String name;
  final String? nameHi;
  final String? pincode;
  final String? cityId;
  final String cityName;
  final double? lat;
  final double? lng;
  final int openSites;
  final DateTime? lastPass;
  final DateTime? nextPass;

  LatLng? get point => lat == null || lng == null ? null : LatLng(lat!, lng!);

  String label(bool hindi) => hindi && nameHi != null ? nameHi! : name;

  factory AreaHit.fromMap(Map<String, dynamic> m) => AreaHit(
    id: m['id'] as String,
    name: m['name'] as String,
    nameHi: m['name_hi'] as String?,
    pincode: m['pincode'] as String?,
    cityId: m['city_id'] as String?,
    cityName: m['city_name'] as String? ?? '',
    lat: asDouble(m['lat']),
    lng: asDouble(m['lng']),
    openSites: asInt(m['open_sites']) ?? 0,
    lastPass: asDate(m['last_pass']),
    nextPass: asDate(m['next_pass']),
  );
}

/// Public counts for the impact page (`impact_summary`).
class Impact {
  const Impact({
    this.sitesFound = 0,
    this.sitesOpen = 0,
    this.sitesCleared = 0,
    this.areaOpenM2 = 0,
    this.complaints = 0,
    this.complaintsOpen = 0,
    this.complaintsResolved = 0,
    this.complaintsProven = 0,
    this.repliedOnTimePct,
    this.medianReplyHours,
    this.fires30d = 0,
    this.byCategory = const {},
  });

  final int sitesFound;
  final int sitesOpen;
  final int sitesCleared;
  final double areaOpenM2;
  final int complaints;
  final int complaintsOpen;
  final int complaintsResolved;
  final int complaintsProven;
  final int? repliedOnTimePct;
  final double? medianReplyHours;
  final int fires30d;
  final Map<String, int> byCategory;

  factory Impact.fromMap(Map<String, dynamic> m) => Impact(
    sitesFound: asInt(m['sites_found']) ?? 0,
    sitesOpen: asInt(m['sites_open']) ?? 0,
    sitesCleared: asInt(m['sites_cleared']) ?? 0,
    areaOpenM2: asDouble(m['area_open_m2']) ?? 0,
    complaints: asInt(m['complaints']) ?? 0,
    complaintsOpen: asInt(m['complaints_open']) ?? 0,
    complaintsResolved: asInt(m['complaints_resolved']) ?? 0,
    complaintsProven: asInt(m['complaints_proven']) ?? 0,
    repliedOnTimePct: asInt(m['replied_on_time_pct']),
    medianReplyHours: asDouble(m['median_reply_hours']),
    fires30d: asInt(m['fires_30d']) ?? 0,
    byCategory: {for (final e in (m['by_category'] as Map? ?? const {}).entries) e.key as String: asInt(e.value) ?? 0},
  );
}
