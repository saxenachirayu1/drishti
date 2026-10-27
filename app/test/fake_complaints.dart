import 'dart:async';
import 'dart:typed_data';

import 'package:drishti/models/ticket.dart';
import 'package:drishti/services/complaints_api.dart';

/// An in-memory backend that behaves like the database for the screens:
/// routing by type, tickets, the timeline and its rules.
class FakeComplaints implements ComplaintsApi {
  FakeComplaints({this.signedIn = true, List<Ticket>? tickets, this.areas = const []})
    : tickets = tickets ?? <Ticket>[];

  bool signedIn;
  final List<Ticket> tickets;
  final List<AreaHit> areas;
  final calls = <String>[];
  final _changes = StreamController<void>.broadcast();
  final _auth = StreamController<void>.broadcast();
  final followed = <String>{};
  int _seq = 411;

  static const me = 'user-me';

  void signIn() {
    signedIn = true;
    _auth.add(null);
  }

  @override
  String? get userId => signedIn ? me : null;

  @override
  Stream<void> get authChanges => _auth.stream;

  @override
  Future<List<AreaHit>> areaLookup(String query) async {
    calls.add('areaLookup:$query');
    final q = query.trim().toLowerCase();
    return [
      for (final a in areas)
        if (a.name.toLowerCase().startsWith(q) || a.pincode == q || (a.nameHi ?? '').startsWith(query.trim())) a,
    ];
  }

  @override
  Future<Impact> impact({String? cityId}) async {
    calls.add('impact:${cityId ?? 'all'}');
    return const Impact(
      sitesFound: 12,
      sitesOpen: 7,
      sitesCleared: 5,
      areaOpenM2: 18400,
      complaints: 40,
      complaintsOpen: 9,
      complaintsResolved: 31,
      complaintsProven: 22,
      repliedOnTimePct: 81,
      medianReplyHours: 4.5,
      fires30d: 3,
      byCategory: {'dump': 20, 'burning': 6, 'bin': 10, 'debris': 4},
    );
  }

  /// Debris east of 73.86 is "on a PWD road" here.
  @override
  Future<RoutePreview> routePreview({required double lat, required double lng, required String category}) async {
    final onRoad = lng > 73.86;
    final dept = category == 'debris' ? (onRoad ? 'pwd' : 'cnd') : 'swm';
    return RoutePreview(
      department: dept,
      onPwdRoad: onRoad,
      replyHours: complaintType(category).replyHours,
      wardNo: 1,
      wardName: 'Demo Ward',
    );
  }

  @override
  Future<Map<String, dynamic>> submit({
    required double lat,
    required double lng,
    required String category,
    String? note,
    Uint8List? photo,
  }) async {
    if (!signedIn) throw StateError('Sign in first');
    calls.add('submit:$category');
    final preview = await routePreview(lat: lat, lng: lng, category: category);
    final now = DateTime.now();
    final code = 'DRI-Q-${(++_seq).toString().padLeft(4, '0')}';
    final t = Ticket(
      id: 'r$_seq',
      ticket: code,
      category: category,
      stage: 'received',
      department: preview.department,
      userId: me,
      wardNo: 1,
      note: note,
      createdAt: now,
      replyDueAt: now.add(Duration(hours: complaintType(category).replyHours)),
      lat: lat,
      lng: lng,
      updates: [TicketUpdate(stage: 'received', authorRole: 'system', message: 'Sent to Ward 1', createdAt: now)],
    );
    tickets.insert(0, t);
    _changes.add(null);
    return {'id': t.id, 'ticket': code, 'status': 'flagged_for_review', 'department': preview.department};
  }

  @override
  Future<List<Ticket>> mine() async => [
    for (final t in tickets)
      if (t.userId == userId) t,
  ];

  @override
  Future<Ticket?> track(String ticketCode) async {
    calls.add('track:$ticketCode');
    for (final t in tickets) {
      if (t.ticket == ticketCode) return t;
    }
    return null;
  }

  @override
  Future<Ticket?> ticket(String reportId) async {
    for (final t in tickets) {
      if (t.id == reportId) return t;
    }
    return null;
  }

  @override
  Future<List<Ticket>> queue({String? department}) async => [
    for (final t in tickets)
      if (department == null || t.department == department) t,
  ];

  @override
  Future<void> postUpdate(String reportId, String stage, {String? message, Uint8List? photo}) async {
    calls.add('post:$reportId:$stage:${message ?? ''}');
    if (stage == 'resolved' && photo == null) throw Exception('attach an after photo to resolve');
    final i = tickets.indexWhere((t) => t.id == reportId);
    final old = tickets[i];
    final now = DateTime.now();
    tickets[i] = Ticket(
      id: old.id,
      ticket: old.ticket,
      category: old.category,
      stage: stage == 'note' ? old.stage : stage,
      department: old.department,
      userId: old.userId,
      wardNo: old.wardNo,
      locality: old.locality,
      createdAt: old.createdAt,
      replyDueAt: old.replyDueAt,
      firstReplyAt: old.firstReplyAt ?? now,
      lat: old.lat,
      lng: old.lng,
      updates: [
        ...old.updates,
        TicketUpdate(stage: stage, authorRole: 'department', message: message, createdAt: now),
      ],
    );
    _changes.add(null);
  }

  @override
  Future<void> transfer(String reportId, String department) async => calls.add('transfer:$reportId:$department');

  @override
  Future<void> reopen(String reportId, {String? reason}) async => calls.add('reopen:$reportId:${reason ?? ''}');

  @override
  Future<Set<String>> follows() async => {...followed};

  @override
  Future<void> setFollow(String localityId, bool on) async {
    calls.add('follow:$localityId:$on');
    if (on) {
      followed.add(localityId);
    } else {
      followed.remove(localityId);
    }
  }

  @override
  Future<String?> photoUrl(String? stored) async => null;

  @override
  Stream<void> ticketChanges(String reportId) => _changes.stream;

  @override
  Stream<void> queueChanges() => _changes.stream;
}

Ticket sampleTicket({
  required String id,
  required String code,
  String category = 'dump',
  String stage = 'received',
  String department = 'swm',
  Duration age = const Duration(hours: 1),
  Duration? repliedAfter,
  String? userId = FakeComplaints.me,
  String? locality = 'Shivajinagar',
}) {
  final created = DateTime.now().subtract(age);
  return Ticket(
    id: id,
    ticket: code,
    category: category,
    stage: stage,
    department: department,
    userId: userId,
    wardNo: 1,
    wardName: 'Demo Ward',
    locality: locality,
    createdAt: created,
    replyDueAt: created.add(Duration(hours: complaintType(category).replyHours)),
    firstReplyAt: repliedAfter == null ? null : created.add(repliedAfter),
    updates: [
      TicketUpdate(stage: 'received', authorRole: 'system', message: 'Sent to Ward 1', createdAt: created),
      if (stage != 'received')
        TicketUpdate(
          stage: stage,
          authorRole: 'department',
          message: 'Team on site',
          createdAt: created.add(repliedAfter ?? Duration.zero),
        ),
    ],
  );
}
