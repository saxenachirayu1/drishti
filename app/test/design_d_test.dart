// Design D: tracking rules, models, and the home, raise, track, console and
// impact screens driven end to end against an in-memory backend.
import 'dart:typed_data';

import 'package:drishti/complaints_providers.dart';
import 'package:drishti/models/place.dart';
import 'package:drishti/models/ticket.dart';
import 'package:drishti/providers.dart';
import 'package:drishti/screens/dept_console_screen.dart';
import 'package:drishti/screens/impact_screen.dart';
import 'package:drishti/screens/landing_screen.dart';
import 'package:drishti/screens/raise_screen.dart';
import 'package:drishti/screens/track_screen.dart';
import 'package:drishti/services/area_search.dart';
import 'package:drishti/services/demo_complaints.dart';
import 'package:drishti/services/drishti_repo.dart';
import 'package:drishti/services/tracking_logic.dart';
import 'package:drishti/theme/d_strings.dart';
import 'package:drishti/theme/drishti_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_complaints.dart';

const _en = DS(false);

const _shivajinagar = AreaHit(
  id: 'loc-pune-shivajinagar',
  name: 'Shivajinagar',
  nameHi: 'शिवाजीनगर',
  pincode: '411005',
  cityId: 'pune',
  cityName: 'Pune',
  lat: 18.5308,
  lng: 73.8475,
  openSites: 2,
);

Future<void> _pump(WidgetTester tester, Widget child, FakeComplaints fake, {Size size = const Size(1280, 1800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        complaintsApiProvider.overrideWithValue(fake),
        liveDeviceProvider.overrideWithValue(false),
        citiesProvider.overrideWith((ref) async => const [City(id: 'pune', name: 'Pune')]),
        // The sign-in form reads the repo; a client that is never called.
        repoProvider.overrideWithValue(
          DrishtiRepo(
            SupabaseClient(
              'http://localhost:9',
              'test-anon-key',
              authOptions: const AuthClientOptions(autoRefreshToken: false),
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: drishtiTheme(),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final f = find.text(text).first;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('tracking rules', () {
    test('a department moves forward only, and closed complaints take notes', () {
      expect(nextStages('received'), ['assigned', 'scheduled', 'in_progress', 'resolved']);
      expect(nextStages('assigned'), ['scheduled', 'in_progress', 'resolved']);
      expect(nextStages('in_progress'), ['resolved']);
      expect(nextStages('reopened'), ['assigned', 'scheduled', 'in_progress', 'resolved']);
      expect(nextStages('resolved'), isEmpty);
      expect(nextStages('proven_clean'), isEmpty);
    });

    test('the ring fills along the lifecycle', () {
      final fills = [for (final s in stages) stageProgress(s)];
      for (var i = 1; i < fills.length; i++) {
        expect(fills[i], greaterThan(fills[i - 1]));
      }
      expect(stageProgress('proven_clean'), 1.0);
    });

    test('reply clock: due, overdue, replied on time and late', () {
      final now = DateTime(2026, 10, 27, 12);
      Ticket t({DateTime? replied, required int hoursAgo, String cat = 'dump'}) {
        final created = now.subtract(Duration(hours: hoursAgo));
        return Ticket(
          id: 'x',
          stage: 'received',
          category: cat,
          createdAt: created,
          replyDueAt: created.add(Duration(hours: complaintType(cat).replyHours)),
          firstReplyAt: replied,
        );
      }

      expect(replyClock(t(hoursAgo: 3), now), isA<DueIn>().having((c) => c.left.inHours, 'left', 21));
      expect(replyClock(t(hoursAgo: 5, cat: 'burning'), now), isA<Overdue>().having((c) => c.by.inHours, 'by', 3));
      expect(
        replyClock(t(hoursAgo: 10, replied: now.subtract(const Duration(hours: 6))), now),
        isA<Replied>().having((c) => c.onTime, 'onTime', true).having((c) => c.took.inHours, 'took', 4),
      );
      expect(replyClock(t(hoursAgo: 30, replied: now), now), isA<Replied>().having((c) => c.onTime, 'onTime', false));
      expect(replyClock(const Ticket(id: 'x', stage: 'received'), now), isA<NoClock>());
    });

    test('queue order: overdue first, then burning, then by deadline, closed last', () {
      final list = [
        sampleTicket(id: 'closed', code: 'DRI-Q-0001', stage: 'resolved', age: const Duration(hours: 40)),
        sampleTicket(id: 'fresh-dump', code: 'DRI-Q-0002', age: const Duration(hours: 1)),
        sampleTicket(id: 'old-dump', code: 'DRI-Q-0003', age: const Duration(hours: 30)),
        sampleTicket(id: 'fire', code: 'DRI-Q-0004', category: 'burning', age: const Duration(minutes: 30)),
        sampleTicket(id: 'older-dump', code: 'DRI-Q-0005', age: const Duration(hours: 50)),
      ];
      expect(
        [for (final t in queueOrder(list, DateTime.now())) t.id],
        ['older-dump', 'old-dump', 'fire', 'fresh-dump', 'closed'],
      );
    });

    test('ticket codes are read forgivingly', () {
      expect(normaliseTicket('DRI-Q-0412'), 'DRI-Q-0412');
      expect(normaliseTicket(' dri q 0412 '), 'DRI-Q-0412');
      expect(normaliseTicket('q-412'), 'DRI-Q-0412');
      expect(normaliseTicket('412'), 'DRI-Q-0412');
      expect(normaliseTicket('12345'), 'DRI-Q-12345');
      expect(normaliseTicket('Q-ABC'), isNull);
      expect(normaliseTicket(''), isNull);
    });

    test('short durations in both languages', () {
      expect(shortDuration(const Duration(minutes: 45)), '45 min');
      expect(shortDuration(const Duration(hours: 3, minutes: 10)), '3 h');
      expect(shortDuration(const Duration(hours: 52)), '2 d 4 h');
      expect(shortDuration(const Duration(hours: 3), hindi: true), '3 घं');
    });

    test('queue filters', () {
      final now = DateTime.now();
      final overdue = sampleTicket(id: 'a', code: 'A', age: const Duration(hours: 30));
      final fire = sampleTicket(id: 'b', code: 'B', category: 'burning');
      final done = sampleTicket(id: 'c', code: 'C', stage: 'proven_clean');
      expect(queueFilterKeeps(QueueFilter.overdue, overdue, now), isTrue);
      expect(queueFilterKeeps(QueueFilter.overdue, fire, now), isFalse);
      expect(queueFilterKeeps(QueueFilter.burning, fire, now), isTrue);
      expect(queueFilterKeeps(QueueFilter.open, done, now), isFalse);
      expect(queueFilterKeeps(QueueFilter.closed, done, now), isTrue);
    });
  });

  group('models', () {
    test('track_report json with its timeline', () {
      final t = Ticket.fromMap({
        'id': 'r1',
        'ticket': 'DRI-Q-0001',
        'category': 'debris',
        'stage': 'in_progress',
        'department': 'pwd',
        'ward_no': 1,
        'ward_name': 'Demo Ward',
        'locality': 'Shivajinagar',
        'created_at': '2026-10-26T09:00:00Z',
        'reply_due_at': '2026-10-28T09:00:00Z',
        'first_reply_at': '2026-10-26T13:00:00Z',
        'updates': [
          {
            'stage': 'received',
            'author_role': 'system',
            'message': 'Sent',
            'has_photo': false,
            'created_at': '2026-10-26T09:00:00Z',
          },
          {
            'stage': 'in_progress',
            'author_role': 'department',
            'has_photo': true,
            'created_at': '2026-10-26T13:00:00Z',
          },
        ],
      });
      expect(t.department, 'pwd');
      expect(t.updates.length, 2);
      expect(t.updates.last.hasPhoto, isTrue);
      expect(t.isClosed, isFalse);
      final c = replyClock(t, DateTime.utc(2026, 10, 27));
      expect(c, isA<Replied>().having((r) => r.took, 'took', const Duration(hours: 4)));
    });

    test('area, impact and route preview rows', () {
      final a = AreaHit.fromMap({
        'id': 'loc-1',
        'name': 'Kothrud',
        'name_hi': 'कोथरुड',
        'pincode': '411038',
        'city_name': 'Pune',
        'lat': 18.5,
        'lng': 73.8,
        'open_sites': 3,
        'last_pass': '2026-10-21',
        'next_pass': '2026-10-31',
      });
      expect(a.label(true), 'कोथरुड');
      expect(a.nextPass, DateTime(2026, 10, 31));
      final i = Impact.fromMap({
        'sites_found': 4,
        'replied_on_time_pct': 75,
        'median_reply_hours': 3.5,
        'by_category': {'dump': 2, 'burning': 1},
      });
      expect(i.byCategory, {'dump': 2, 'burning': 1});
      expect(i.medianReplyHours, 3.5);
      expect(Impact.fromMap({}).repliedOnTimePct, isNull);
      final r = RoutePreview.fromMap({'department': 'pwd', 'on_pwd_road': true, 'reply_hours': 48, 'ward_no': 1});
      expect(r.onPwdRoad, isTrue);
    });

    test('every complaint type has text in both languages', () {
      for (final hindi in [false, true]) {
        final ds = DS(hindi);
        for (final c in complaintTypes) {
          expect(ds.typeName(c.id), isNot(c.id));
          expect(ds.typeHint(c.id), isNotEmpty);
        }
        for (final s in [...stages, 'reopened']) {
          expect(ds.headline(s), isNot(s));
        }
      }
    });
  });

  group('home page', () {
    testWidgets('area search: hit, miss, empty, and the map link', (tester) async {
      final fake = FakeComplaints(areas: const [_shivajinagar]);
      await _pump(tester, const LandingScreen(), fake);
      expect(find.text(_en.h1), findsOneWidget);

      await _tapText(tester, _en.searchBtn);
      expect(find.text(_en.searchEmptyTitle), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('area-search')), 'shiva');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Shivajinagar, Pune · 411005'), findsOneWidget);
      expect(find.text(_en.openRecords(2)), findsOneWidget);
      expect(find.text(_en.seeOnMap), findsOneWidget);
      expect(fake.calls, contains('areaLookup:shiva'));

      await tester.enterText(find.byKey(const ValueKey('area-search')), 'Timbuktu');
      await _tapText(tester, _en.searchBtn);
      expect(find.text(_en.searchMissTitle), findsOneWidget);
      expect(find.text(_en.seeOnMap), findsNothing);
    });

    testWidgets('follow the searched area', (tester) async {
      final fake = FakeComplaints(areas: const [_shivajinagar]);
      await _pump(tester, const LandingScreen(), fake);
      expect(find.text(_en.followFind), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('area-search')), '411005');
      await _tapText(tester, _en.searchBtn);
      await _tapText(tester, _en.follow('Shivajinagar'));
      expect(fake.calls, contains('follow:loc-pune-shivajinagar:true'));
      expect(find.text(_en.following('Shivajinagar')), findsOneWidget);

      await _tapText(tester, _en.following('Shivajinagar'));
      expect(fake.calls, contains('follow:loc-pune-shivajinagar:false'));
      expect(find.text(_en.follow('Shivajinagar')), findsOneWidget);
    });

    testWidgets('journey stages and the Hindi switch', (tester) async {
      await _pump(tester, const LandingScreen(), FakeComplaints());
      expect(find.text(_en.journeyText[0]), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('stop-3')));
      await tester.tap(find.byKey(const ValueKey('stop-3')));
      await tester.pumpAndSettle();
      expect(find.text(_en.journeyText[3]), findsOneWidget);

      await tester.ensureVisible(find.text('हिं'));
      await tester.tap(find.text('हिं'));
      await tester.pumpAndSettle();
      expect(find.text(const DS(true).h1), findsOneWidget);
      expect(find.text(const DS(true).journeyText[3]), findsOneWidget);
    });

    testWidgets('the before/after picture can be dragged', (tester) async {
      await _pump(tester, const LandingScreen(), FakeComplaints());
      final pic = find.byKey(const ValueKey('before-after-drag'));
      expect(pic, findsOneWidget);
      await tester.drag(pic, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a phone without overflow', (tester) async {
      await _pump(tester, const LandingScreen(), FakeComplaints(), size: const Size(360, 2400));
      expect(tester.takeException(), isNull);
      expect(find.text(_en.raise), findsWidgets);
    });
  });

  group('raise a complaint', () {
    testWidgets('routes by type and files with a ticket code', (tester) async {
      final fake = FakeComplaints();
      await _pump(tester, const RaiseScreen(), fake);

      expect(find.text(_en.deptName('swm')), findsOneWidget);
      expect(find.text(_en.replyTarget(24)), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('type-burning')));
      await tester.pumpAndSettle();
      expect(find.text(_en.replyTarget(2)), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('type-debris')));
      await tester.pumpAndSettle();
      expect(find.text(_en.deptName('cnd')), findsOneWidget);
      expect(find.text(_en.replyTarget(48)), findsOneWidget);

      // Sending without a place asks for one.
      await tester.tap(find.byKey(const ValueKey('raise-submit')));
      await tester.pumpAndSettle();
      expect(find.text(_en.pickPlaceFirst), findsOneWidget);
      expect(fake.calls.where((c) => c.startsWith('submit')), isEmpty);

      // Tap the east of the map: the fake says that is a PWD road.
      final map = find.byType(FlutterMap);
      await tester.ensureVisible(map);
      await tester.pumpAndSettle();
      final box = tester.getRect(map);
      await tester.tapAt(Offset(box.right - 20, box.center.dy));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ward 1 · Demo Ward · ${_en.deptName('pwd')}'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('raise-note')), 'Rubble across the lane');
      ScaffoldMessenger.of(tester.element(find.byType(RaiseScreen))).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('raise-submit')));
      await tester.pumpAndSettle();
      expect(fake.calls, contains('submit:debris'));
      expect(find.text(_en.sentTitle), findsOneWidget);
      expect(find.text('DRI-Q-0412'), findsOneWidget);
      expect(fake.tickets.single.note, 'Rubble across the lane');

      await tester.tap(find.text(_en.done));
      await tester.pumpAndSettle();
      expect(find.text(_en.sentTitle), findsNothing);
    });

    testWidgets('signed out, it asks to sign in first', (tester) async {
      await _pump(tester, const RaiseScreen(), FakeComplaints(signedIn: false));
      expect(find.text(_en.signInToRaise), findsOneWidget);
      expect(find.byKey(const ValueKey('raise-submit')), findsNothing);
    });
  });

  group('track a complaint', () {
    testWidgets('by code, public view with the timeline', (tester) async {
      final fake = FakeComplaints(
        signedIn: false,
        tickets: [
          sampleTicket(
            id: 'r9',
            code: 'DRI-Q-0412',
            stage: 'in_progress',
            userId: 'someone-else',
            repliedAfter: const Duration(hours: 4),
            age: const Duration(hours: 20),
          ),
        ],
      );
      await _pump(tester, const TrackScreen(), fake);

      await tester.enterText(find.byKey(const ValueKey('ticket-code')), 'abc');
      await _tapText(tester, _en.searchBtn);
      expect(find.text(_en.ticketBad), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('ticket-code')), 'q 412');
      await _tapText(tester, _en.searchBtn);
      expect(fake.calls, contains('track:DRI-Q-0412'));
      expect(find.text(_en.headline('in_progress')), findsOneWidget);
      expect(find.text('Team on site'), findsOneWidget);
      expect(find.text(_en.nextProof), findsOneWidget);
      expect(find.textContaining('First reply in 4 h ✓'), findsOneWidget);
      // Public view: no live badge, no reopen.
      expect(find.text('● ${_en.live}'), findsNothing);
      expect(find.byKey(const ValueKey('reopen')), findsNothing);
    });

    testWidgets('your own complaints update live and can be reopened', (tester) async {
      final fake = FakeComplaints(
        tickets: [
          sampleTicket(id: 'r1', code: 'DRI-Q-0001', stage: 'resolved', repliedAfter: const Duration(hours: 2)),
        ],
      );
      await _pump(tester, const TrackScreen(), fake);
      expect(find.text(_en.yourComplaints), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ticket-r1')));
      await tester.pumpAndSettle();
      expect(find.text('● ${_en.live}'), findsOneWidget);
      expect(find.text(_en.headline('resolved')), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('reopen')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('reopen-reason')), 'Back again');
      await tester.tap(find.text(_en.reopenSend));
      await tester.pumpAndSettle();
      expect(fake.calls, contains('reopen:r1:Back again'));

      // A department update arrives: the open timeline shows it without a reload.
      await fake.postUpdate('r1', 'note', message: 'Inspector visiting at 4 pm');
      await tester.pumpAndSettle();
      expect(find.text('Inspector visiting at 4 pm'), findsOneWidget);
    });
  });

  group('department console', () {
    testWidgets('queue, filters, and posting an update', (tester) async {
      final fake = FakeComplaints(
        tickets: [
          sampleTicket(id: 'fresh', code: 'DRI-Q-0002', age: const Duration(hours: 1), userId: 'u2'),
          sampleTicket(id: 'late', code: 'DRI-Q-0003', age: const Duration(hours: 30), userId: 'u3'),
          sampleTicket(id: 'fire', code: 'DRI-Q-0004', category: 'burning', userId: 'u4'),
          sampleTicket(id: 'pwd', code: 'DRI-Q-0005', category: 'debris', department: 'pwd', userId: 'u5'),
        ],
      );
      await _pump(tester, const DeptConsoleScreen(), fake, size: const Size(1400, 1400));

      expect(find.text(_en.nOverdue(1)), findsOneWidget);
      expect(find.text(_en.nOpen(4)), findsOneWidget);
      // Overdue comes first.
      final ys = [
        for (final id in ['late', 'fire', 'fresh']) tester.getTopLeft(find.byKey(ValueKey('ticket-$id'))).dy,
      ];
      expect(ys[0], lessThan(ys[1]));
      expect(ys[1], lessThan(ys[2]));

      await tester.tap(find.byKey(const ValueKey('filter-burning')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ticket-fire')), findsOneWidget);
      expect(find.byKey(const ValueKey('ticket-late')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('filter-open')));
      await tester.pumpAndSettle();

      // Only PWD.
      await tester.tap(find.byKey(const ValueKey('dept-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.deptName('pwd')).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ticket-pwd')), findsOneWidget);
      expect(find.byKey(const ValueKey('ticket-late')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('ticket-pwd')));
      await tester.pumpAndSettle();
      // Resolving needs a photo; the console says so before calling the server.
      await tester.tap(find.byKey(const ValueKey('stage-resolved')));
      await tester.pumpAndSettle();
      expect(find.text(_en.resolveNote), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('post-update')));
      await tester.pumpAndSettle();
      expect(find.text(_en.needPhoto), findsOneWidget);
      expect(fake.calls.where((c) => c.startsWith('post:')), isEmpty);

      await tester.tap(find.byKey(const ValueKey('stage-assigned')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('dept-message')), 'Road division inspector assigned');
      await tester.tap(find.byKey(const ValueKey('post-update')));
      await tester.pumpAndSettle();
      expect(fake.calls, contains('post:pwd:assigned:Road division inspector assigned'));
      expect(find.text('Road division inspector assigned'), findsOneWidget);
      // Assigned is now behind it, so it is no longer offered.
      expect(find.byKey(const ValueKey('stage-assigned')), findsNothing);
    });

    testWidgets('the board reads but cannot post', (tester) async {
      final fake = FakeComplaints(
        tickets: [sampleTicket(id: 'a', code: 'DRI-Q-0002', userId: 'u2')],
      );
      await _pump(tester, const DeptConsoleScreen(canAct: false), fake, size: const Size(1400, 1200));
      await tester.tap(find.byKey(const ValueKey('ticket-a')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('post-update')), findsNothing);
      expect(find.byKey(const ValueKey('transfer')), findsNothing);
    });
  });

  group('impact', () {
    testWidgets('counts from the records and the cited national figure', (tester) async {
      final fake = FakeComplaints();
      await _pump(tester, const ImpactScreen(), fake);
      expect(find.text('81%'), findsOneWidget);
      expect(find.text('4.5 h'), findsOneWidget);
      expect(find.text(_en.goalSource), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('city-pune')));
      await tester.pumpAndSettle();
      expect(fake.calls, contains('impact:pune'));
    });
  });

  group('demo mode', () {
    test('sample data, routing, the full lifecycle and impact', () async {
      final demo = DemoComplaints();
      expect((await demo.areaLookup('kot')).single.name, 'Kothrud');
      expect((await demo.areaLookup('411005')).single.name, 'Shivajinagar');
      expect(await demo.mine(), isNotEmpty);
      expect((await demo.queue()).length, 6);
      expect((await demo.track('DRI-Q-0409'))!.stage, 'in_progress');

      expect((await demo.routePreview(lat: 18.5151, lng: 73.86, category: 'debris')).department, 'pwd');
      expect((await demo.routePreview(lat: 18.53, lng: 73.86, category: 'debris')).department, 'cnd');
      final burn = await demo.routePreview(lat: 18.53, lng: 73.85, category: 'burning');
      expect(burn.department, 'swm');
      expect(burn.wardNo, 1);
      expect(burn.replyHours, 2);

      final res = await demo.submit(lat: 18.531, lng: 73.848, category: 'dump', note: 'Heap by the wall');
      final id = res['id'] as String;
      expect(res['ticket'], 'DRI-Q-0411');
      final mine = await demo.mine();
      expect(mine.first.id, id);
      expect(mine.first.locality, 'Shivajinagar');

      await demo.postUpdate(id, 'assigned', message: 'Inspector assigned');
      expect((await demo.ticket(id))!.firstReplyAt, isNotNull);
      expect(() => demo.postUpdate(id, 'resolved'), throwsStateError);
      await demo.postUpdate(id, 'resolved', message: 'Cleared', photo: Uint8List.fromList([1, 2, 3]));
      expect((await demo.ticket(id))!.stage, 'resolved');
      expect(await demo.photoUrl((await demo.ticket(id))!.updates.last.photoPath), startsWith('data:image/jpeg;base64,'));
      await demo.simulateSatelliteClear(id);
      expect((await demo.ticket(id))!.stage, 'proven_clean');
      await demo.reopen(id, reason: 'Back again');
      expect((await demo.ticket(id))!.stage, 'reopened');

      final i = await demo.impact();
      expect(i.complaints, 7);
      expect(i.byCategory['dump'], 3);
      expect(i.repliedOnTimePct, isNotNull);
    });

    testWidgets('raise then work it in the console, on demo data', (tester) async {
      final demo = DemoComplaints();
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          complaintsApiProvider.overrideWithValue(demo),
          liveDeviceProvider.overrideWithValue(false),
        ],
        child: MaterialApp(theme: drishtiTheme(), home: const Scaffold(body: DeptConsoleScreen())),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ticket-demo-409')), findsOneWidget);
      expect(find.text(_en.nOverdue(2)), findsOneWidget); // the bin and the burning, both unanswered

      await demo.submit(lat: 18.531, lng: 73.848, category: 'burning');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ticket-demo-411')), findsOneWidget);
    });
  });

  group('PIN code search', () {
    test('reads PIN codes forgivingly and rejects ones that cannot exist', () {
      expect(parseAreaQuery('411005'), isA<PinQuery>().having((q) => q.pin, 'pin', '411005'));
      expect(parseAreaQuery(' 411 005 '), isA<PinQuery>().having((q) => q.pin, 'pin', '411005'));
      expect(parseAreaQuery('411-005'), isA<PinQuery>().having((q) => q.pin, 'pin', '411005'));
      expect(parseAreaQuery('41100'), isA<BadPin>());
      expect(parseAreaQuery('011005'), isA<BadPin>());
      expect(parseAreaQuery('4110055'), isA<BadPin>());
      expect(parseAreaQuery('k'), isA<TooShort>());
      expect(parseAreaQuery('Kothrud'), isA<NameQuery>());
    });

    test('every PIN in the four live cities resolves; others do not', () {
      expect(localAreaLookup('411005').single.name, 'Shivajinagar');
      expect(localAreaLookup('411001').single, isA<AreaHit>().having((a) => a.cityName, 'city', 'Pune'));
      expect(localAreaLookup('412105').single.cityName, 'Pune');
      expect(localAreaLookup('110001').single.cityName, 'Delhi');
      expect(localAreaLookup('452001').single.cityName, 'Indore');
      expect(localAreaLookup('462011').single.cityName, 'Bhopal');
      expect(localAreaLookup('411001').single.isNamedArea, isFalse);
      expect(localAreaLookup('411001').single.openSites, isNull);
      expect(localAreaLookup('576104'), isEmpty); // Manipal: not covered yet
      expect(localAreaLookup('pune').map((a) => a.name), contains('Pune'));
      final (last, next) = passesAround(DateTime(2026, 10, 27, 15));
      expect(next.difference(last).inDays, 5);
      expect(!last.isAfter(DateTime(2026, 10, 27)) && next.isAfter(DateTime(2026, 10, 27)), isTrue);
    });

    testWidgets('home page: a city PIN, a bad PIN and an uncovered PIN', (tester) async {
      await _pump(tester, const LandingScreen(), DemoComplaints());
      Future<void> search(String q) async {
        await tester.enterText(find.byKey(const ValueKey('area-search')), q);
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
      }

      await search('411001');
      expect(find.text(_en.pinTitle('411001', 'Pune')), findsOneWidget);
      expect(find.textContaining(_en.coveredCity('Pune')), findsOneWidget);
      expect(find.text(_en.seeOnMap), findsOneWidget);
      expect(find.text(_en.followNamed), findsOneWidget);

      await search('411 005');
      expect(find.text('Shivajinagar, Pune · 411005'), findsOneWidget);
      expect(find.textContaining(_en.openRecords(2)), findsOneWidget);

      await search('4110');
      expect(find.text(_en.badPinTitle), findsOneWidget);

      await search('576104');
      expect(find.text(_en.searchMissTitle), findsOneWidget);
    });
  });
}
