import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../models/ticket.dart';
import 'complaints_api.dart';

/// Demo mode (`--dart-define=DEMO=true`): the complaint features run on
/// sample data in memory, so the app can be shown on localhost with no
/// database or keys. The same routing rules as the database apply, and the
/// app shows a DEMO banner the whole time. Nothing is saved.
class DemoComplaints implements ComplaintsApi {
  DemoComplaints({DateTime? now}) {
    _seed(now ?? DateTime.now());
  }

  /// The demo resident is always signed in.
  static const citizenId = 'demo-resident';

  final _tickets = <Ticket>[];
  final _photos = <String, Uint8List>{};
  final _follows = <String>{};
  final _changes = StreamController<void>.broadcast();
  int _seq = 410;

  @override
  String? get userId => citizenId;

  @override
  Stream<void> get authChanges => const Stream.empty();

  // --- places -------------------------------------------------------------

  static const _pune = '11111111-1111-1111-1111-111111111111';

  static final areas = <AreaHit>[
    _area('loc-pune-shivajinagar', 'Shivajinagar', 'शिवाजीनगर', '411005', 18.5308, 73.8475, open: 2),
    _area('loc-pune-deccan', 'Deccan Gymkhana', 'डेक्कन जिमखाना', '411004', 18.5167, 73.8411, open: 1),
    _area('loc-pune-kothrud', 'Kothrud', 'कोथरुड', '411038', 18.5074, 73.8077, open: 3),
    _area('loc-pune-aundh', 'Aundh', 'औंध', '411007', 18.5590, 73.8070, open: 0),
    _area('loc-ind-rau', 'Rau', 'राऊ', '453331', 22.6360, 75.8110, city: 'Indore', cityId: 'indore', open: 2),
    _area('loc-ind-sudama', 'Sudama Nagar', 'सुदामा नगर', '452009', 22.6900, 75.8300,
        city: 'Indore', cityId: 'indore', open: 1),
    _area('loc-bho-kolar', 'Kolar Road', 'कोलार रोड', '462042', 23.1800, 77.4100, city: 'Bhopal', cityId: 'bhopal', open: 1),
    _area('loc-del-okhla', 'Okhla', 'ओखला', '110020', 28.5300, 77.2700, city: 'Delhi', cityId: 'delhi', open: 0),
  ];

  static AreaHit _area(String id, String name, String hi, String pin, double lat, double lng,
      {String city = 'Pune', String cityId = _pune, int open = 0}) {
    final today = DateTime.now();
    final last = DateTime(today.year, today.month, today.day).subtract(Duration(days: (today.day % 5) + 1));
    return AreaHit(
      id: id,
      name: name,
      nameHi: hi,
      pincode: pin,
      cityId: cityId,
      cityName: city,
      lat: lat,
      lng: lng,
      openSites: open,
      lastPass: last,
      nextPass: last.add(const Duration(days: 5)),
    );
  }

  /// The demo ward (same box as the seed data) and the demo PWD road.
  static bool _inDemoWard(double lat, double lng) => lat >= 18.50 && lat <= 18.54 && lng >= 73.84 && lng <= 73.88;
  static bool _onPwdRoad(double lat, double lng) => (lat - 18.515).abs() < 0.0003 && lng >= 73.845 && lng <= 73.875;

  String? _nearestLocality(double lat, double lng) {
    AreaHit? best;
    var bestD = double.infinity;
    for (final a in areas) {
      final d = (a.lat! - lat) * (a.lat! - lat) + (a.lng! - lng) * (a.lng! - lng);
      if (d < bestD) {
        bestD = d;
        best = a;
      }
    }
    return bestD < 0.03 * 0.03 ? best?.name : null; // about 3 km
  }

  // --- reads -----------------------------------------------------------------

  @override
  Future<List<AreaHit>> areaLookup(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final lower = q.toLowerCase();
    return [
      for (final a in areas)
        if (a.name.toLowerCase().startsWith(lower) || a.pincode == q || (a.nameHi ?? '').startsWith(q)) a,
    ].take(5).toList();
  }

  @override
  Future<RoutePreview> routePreview({required double lat, required double lng, required String category}) async {
    final onRoad = _onPwdRoad(lat, lng);
    final inWard = _inDemoWard(lat, lng);
    return RoutePreview(
      department: _route(category, onRoad),
      onPwdRoad: onRoad,
      replyHours: complaintType(category).replyHours,
      wardNo: inWard ? 1 : null,
      wardName: inWard ? 'Demo Ward' : null,
    );
  }

  static String _route(String category, bool onRoad) => category == 'debris' ? (onRoad ? 'pwd' : 'cnd') : 'swm';

  @override
  Future<List<Ticket>> mine() async => [
        for (final t in _tickets)
          if (t.userId == citizenId) t,
      ];

  @override
  Future<Ticket?> track(String ticketCode) async {
    for (final t in _tickets) {
      if (t.ticket == ticketCode) return t;
    }
    return null;
  }

  @override
  Future<Ticket?> ticket(String reportId) async {
    for (final t in _tickets) {
      if (t.id == reportId) return t;
    }
    return null;
  }

  @override
  Future<List<Ticket>> queue({String? department}) async => [
        for (final t in _tickets)
          if (department == null || t.department == department) t,
      ];

  @override
  Future<Impact> impact({String? cityId}) async {
    final list = cityId == null || cityId == _pune ? _tickets : const <Ticket>[];
    final replied = list.where((t) => t.firstReplyAt != null).toList();
    final dueOrReplied = list.where((t) => t.firstReplyAt != null || (t.replyDueAt?.isBefore(DateTime.now()) ?? false));
    final onTime = replied.where((t) => !t.firstReplyAt!.isAfter(t.replyDueAt!)).length;
    final hours = [for (final t in replied) t.firstReplyAt!.difference(t.createdAt!).inMinutes / 60]..sort();
    final byCat = <String, int>{};
    for (final t in list) {
      byCat[t.category] = (byCat[t.category] ?? 0) + 1;
    }
    // Satellite sites: the demo seed's numbers, by city.
    final sites = switch (cityId) {
      null => (12, 7, 5, 18400.0),
      _pune => (3, 2, 1, 4100.0),
      'indore' => (5, 3, 2, 8200.0),
      'bhopal' => (3, 2, 1, 6100.0),
      _ => (1, 0, 1, 0.0),
    };
    return Impact(
      sitesFound: sites.$1,
      sitesOpen: sites.$2,
      sitesCleared: sites.$3,
      areaOpenM2: sites.$4,
      complaints: list.length,
      complaintsOpen: list.where((t) => !t.isClosed).length,
      complaintsResolved: list.where((t) => t.isClosed).length,
      complaintsProven: list.where((t) => t.stage == 'proven_clean').length,
      repliedOnTimePct: dueOrReplied.isEmpty ? null : (100 * onTime / dueOrReplied.length).round(),
      medianReplyHours: hours.isEmpty ? null : hours[hours.length ~/ 2],
      fires30d: cityId == null || cityId == 'indore' ? 3 : 0,
      byCategory: byCat,
    );
  }

  @override
  Future<Set<String>> follows() async => {..._follows};

  @override
  Future<String?> photoUrl(String? stored) async {
    final bytes = stored == null ? null : _photos[stored];
    return bytes == null ? null : 'data:image/jpeg;base64,${base64Encode(bytes)}';
  }

  @override
  Stream<void> ticketChanges(String reportId) => _changes.stream;

  @override
  Stream<void> queueChanges() => _changes.stream;

  // --- writes -------------------------------------------------------------

  @override
  Future<Map<String, dynamic>> submit({
    required double lat,
    required double lng,
    required String category,
    String? note,
    Uint8List? photo,
  }) async {
    final now = DateTime.now();
    final onRoad = _onPwdRoad(lat, lng);
    final inWard = _inDemoWard(lat, lng);
    final dept = _route(category, onRoad);
    final id = 'demo-${++_seq}';
    String? stored;
    if (photo != null) {
      stored = 'demo/$id.jpg';
      _photos[stored] = photo;
    }
    final code = 'DRI-Q-${_seq.toString().padLeft(4, '0')}';
    _tickets.insert(
      0,
      Ticket(
        id: id,
        ticket: code,
        category: category,
        stage: 'received',
        department: dept,
        userId: citizenId,
        wardNo: inWard ? 1 : null,
        wardName: inWard ? 'Demo Ward' : null,
        locality: _nearestLocality(lat, lng),
        note: note,
        photoUrl: stored,
        createdAt: now,
        replyDueAt: now.add(Duration(hours: complaintType(category).replyHours)),
        lat: lat,
        lng: lng,
        updates: [
          TicketUpdate(
            stage: 'received',
            authorRole: 'system',
            message: 'Sent to ${inWard ? 'Ward 1 · ' : ''}${_deptName[dept]}',
            createdAt: now,
          ),
        ],
      ),
    );
    _changes.add(null);
    return {'id': id, 'ticket': code, 'status': 'flagged_for_review', 'department': dept};
  }

  static const _deptName = {
    'swm': 'Municipal Solid Waste Management office',
    'pwd': 'PWD road division',
    'cnd': 'Municipal C&D waste cell',
  };

  int _index(String id) {
    final i = _tickets.indexWhere((t) => t.id == id);
    if (i < 0) throw StateError('No complaint $id');
    return i;
  }

  @override
  Future<void> postUpdate(String reportId, String stage, {String? message, Uint8List? photo}) async {
    final i = _index(reportId);
    final t = _tickets[i];
    if (stage == 'resolved' && photo == null) throw StateError('Attach an after photo to resolve');
    String? stored;
    if (photo != null) {
      stored = 'demo/$reportId-${t.updates.length}.jpg';
      _photos[stored] = photo;
    }
    final now = DateTime.now();
    _tickets[i] = _copy(
      t,
      stage: stage == 'note' ? t.stage : stage,
      firstReplyAt: t.firstReplyAt ?? now,
      resolvedAt: stage == 'resolved' ? now : t.resolvedAt,
      updates: [
        ...t.updates,
        TicketUpdate(stage: stage, authorRole: 'department', message: message, photoPath: stored, createdAt: now),
      ],
    );
    _changes.add(null);
  }

  @override
  Future<void> transfer(String reportId, String department) async {
    final i = _index(reportId);
    final t = _tickets[i];
    _tickets[i] = _copy(t, department: department, updates: [
      ...t.updates,
      TicketUpdate(
        stage: 'note',
        authorRole: 'department',
        message: 'Transferred to ${_deptName[department]}',
        createdAt: DateTime.now(),
      ),
    ]);
    _changes.add(null);
  }

  @override
  Future<void> reopen(String reportId, {String? reason}) async {
    final i = _index(reportId);
    final t = _tickets[i];
    final now = DateTime.now();
    _tickets[i] = _copy(t, stage: 'reopened', resolvedAt: null, clearResolved: true,
        replyDueAt: now.add(Duration(hours: complaintType(t.category).replyHours)),
        updates: [
          ...t.updates,
          TicketUpdate(
            stage: 'reopened',
            authorRole: 'citizen',
            message: (reason ?? '').isEmpty ? 'Not fixed yet' : reason,
            createdAt: now,
          ),
        ]);
    _changes.add(null);
  }

  @override
  Future<void> setFollow(String localityId, bool on) async {
    if (on) {
      _follows.add(localityId);
    } else {
      _follows.remove(localityId);
    }
  }

  /// Marks a resolved complaint proven clean, as the database does when the
  /// next satellite passes show the site clear. The console offers this in
  /// demo mode so the whole story can be shown in one sitting.
  Future<void> simulateSatelliteClear(String reportId) async {
    final i = _index(reportId);
    final t = _tickets[i];
    if (t.stage != 'resolved') return;
    _tickets[i] = _copy(t, stage: 'proven_clean', updates: [
      ...t.updates,
      TicketUpdate(
        stage: 'proven_clean',
        authorRole: 'system',
        message: 'The satellite shows the site clear on two passes.',
        createdAt: DateTime.now(),
      ),
    ]);
    _changes.add(null);
  }

  Ticket _copy(
    Ticket t, {
    String? stage,
    String? department,
    DateTime? firstReplyAt,
    DateTime? resolvedAt,
    bool clearResolved = false,
    DateTime? replyDueAt,
    List<TicketUpdate>? updates,
  }) =>
      Ticket(
        id: t.id,
        ticket: t.ticket,
        category: t.category,
        stage: stage ?? t.stage,
        department: department ?? t.department,
        userId: t.userId,
        wardNo: t.wardNo,
        wardName: t.wardName,
        locality: t.locality,
        note: t.note,
        photoUrl: t.photoUrl,
        linkedSiteId: t.linkedSiteId,
        createdAt: t.createdAt,
        replyDueAt: replyDueAt ?? t.replyDueAt,
        firstReplyAt: firstReplyAt ?? t.firstReplyAt,
        resolvedAt: clearResolved ? null : (resolvedAt ?? t.resolvedAt),
        updatedAt: DateTime.now(),
        lat: t.lat,
        lng: t.lng,
        updates: updates ?? t.updates,
      );

  // --- sample data -------------------------------------------------------------

  void _seed(DateTime now) {
    Ticket make(
      int n, {
      required String category,
      required String dept,
      required String locality,
      required Duration age,
      required List<(String, Duration, String, String)> steps, // stage, after, role, message
      String? user = 'someone-else',
      String? site,
      bool inWard = true,
      String? note,
    }) {
      final created = now.subtract(age);
      final ups = <TicketUpdate>[
        TicketUpdate(
          stage: 'received',
          authorRole: 'system',
          message: 'Sent to ${inWard ? 'Ward 1 · ' : ''}${_deptName[dept]}',
          createdAt: created,
        ),
        for (final s in steps) TicketUpdate(stage: s.$1, authorRole: s.$3, message: s.$4, createdAt: created.add(s.$2)),
      ];
      final firstDept = steps.where((s) => s.$3 == 'department').map((s) => created.add(s.$2)).firstOrNullValue;
      final last = ups.lastWhere((u) => u.stage != 'note').stage;
      return Ticket(
        id: 'demo-$n',
        ticket: 'DRI-Q-${n.toString().padLeft(4, '0')}',
        category: category,
        stage: last,
        department: dept,
        userId: user,
        wardNo: inWard ? 1 : null,
        wardName: inWard ? 'Demo Ward' : null,
        locality: locality,
        note: note,
        linkedSiteId: site,
        createdAt: created,
        replyDueAt: created.add(Duration(hours: complaintType(category).replyHours)),
        firstReplyAt: firstDept,
        resolvedAt: last == 'resolved' || last == 'proven_clean' ? ups.last.createdAt : null,
        lat: 18.52,
        lng: 73.855,
        updates: ups,
      );
    }

    _tickets.addAll([
      make(
        407,
        category: 'bin',
        dept: 'swm',
        locality: 'Deccan Gymkhana',
        age: const Duration(hours: 30),
        steps: const [],
        note: 'Bin overflowing for two days',
      ),
      make(
        408,
        category: 'burning',
        dept: 'swm',
        locality: 'Shivajinagar',
        age: const Duration(hours: 5),
        steps: const [],
        note: 'Smoke behind the market since morning',
      ),
      make(
        409,
        category: 'dump',
        dept: 'swm',
        locality: 'Shivajinagar',
        age: const Duration(hours: 20),
        site: 'site-5',
        user: citizenId,
        note: 'Behind the bus stop',
        steps: const [
          ('assigned', Duration(hours: 4), 'department', 'Sanitary Inspector, Ward 1 assigned.'),
          ('scheduled', Duration(hours: 11), 'department', 'Clearing planned for this afternoon.'),
          ('in_progress', Duration(hours: 18), 'department', 'Team of 4 on site with a tipper truck.'),
        ],
      ),
      make(
        402,
        category: 'debris',
        dept: 'pwd',
        locality: 'Shivajinagar',
        age: const Duration(days: 6),
        user: citizenId,
        note: 'Rubble across the road edge',
        steps: const [
          ('assigned', Duration(hours: 9), 'department', 'Road division inspector assigned.'),
          ('in_progress', Duration(days: 2), 'department', 'Debris being lifted.'),
          ('resolved', Duration(days: 3), 'department', 'Road edge cleared.'),
          ('proven_clean', Duration(days: 5), 'system', 'The satellite shows the site clear on two passes.'),
        ],
      ),
      make(
        404,
        category: 'dump',
        dept: 'swm',
        locality: 'Kothrud',
        inWard: false,
        age: const Duration(days: 3),
        steps: const [
          ('assigned', Duration(hours: 30), 'department', 'Assigned to the ward team.'),
          ('resolved', Duration(days: 2), 'department', 'Heap removed and area sprayed.'),
        ],
      ),
      make(
        405,
        category: 'debris',
        dept: 'cnd',
        locality: 'Deccan Gymkhana',
        age: const Duration(hours: 10),
        steps: const [],
      ),
    ]);
    _tickets.sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
  }
}

extension on Iterable<DateTime> {
  DateTime? get firstOrNullValue => isEmpty ? null : first;
}
