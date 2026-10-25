// End-to-end test of the app's data layer against the real Supabase project.
// Skipped unless DRISHTI_LIVE=1. Needs three users (citizen, officer, admin)
// with these roles in public.profiles:
//
//   DRISHTI_LIVE=1 E2E_PASSWORD=... E2E_CITIZEN=a@x E2E_OFFICER=b@x E2E_ADMIN=c@x flutter test test/live_supabase_test.dart
//
// It writes test complaints, reports and runs; clean them up afterwards.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drishti/config.dart';
import 'package:drishti/services/action_engine.dart';
import 'package:drishti/services/api_client.dart';
import 'package:drishti/services/drishti_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

final _env = Platform.environment;
final _live = _env['DRISHTI_LIVE'] == '1';

DrishtiRepo _client() => DrishtiRepo(SupabaseClient(AppConfig.supabaseUrl, AppConfig.supabaseAnonKey,
    authOptions: const AuthClientOptions(autoRefreshToken: false)));

ActionEngine _local(DrishtiRepo repo) => ActionEngine(repo, DrishtiApi('', () => repo.accessToken));

/// A small JPEG carrying EXIF (camera make and model), like a phone photo.
Uint8List _photoWithExif() {
  final image = img.Image(width: 32, height: 24)..clear(img.ColorRgb8(120, 90, 60));
  image.exif.imageIfd['Make'] = img.IfdValueAscii('E2E Phone');
  image.exif.imageIfd['Model'] = img.IfdValueAscii('Model X');
  final bytes = img.encodeJpg(image);
  assert(img.decodeJpg(bytes)!.exif.imageIfd['Make'] != null);
  return Uint8List.fromList(bytes);
}

void main() {
  final anon = _client();
  final citizen = _client();
  final officer = _client();
  final admin = _client();
  final pw = _env['E2E_PASSWORD'] ?? '';

  setUpAll(() async {
    if (!_live) return;
    await citizen.signIn(_env['E2E_CITIZEN']!, pw);
    await officer.signIn(_env['E2E_OFFICER']!, pw);
    await admin.signIn(_env['E2E_ADMIN']!, pw);
  });

  group('public map (anon key)', skip: !_live, () {
    test('cities from both B and C configs', () async {
      final ids = (await anon.cities()).map((c) => c.id).toSet();
      expect(ids, containsAll(['indore', 'bhopal', '11111111-1111-1111-1111-111111111111']));
    });

    test('sites: low-confidence site hidden, wards assigned, record check', () async {
      final sites = await anon.sites();
      final ids = sites.map((s) => s.id).toSet();
      expect(ids, containsAll(['site-1', 'site-2', 'site-3', 'site-5']));
      expect(ids, isNot(contains('site-4')), reason: 'confidence 0.45 < 0.6 stays off the public map (N-06)');
      for (final s in sites) {
        expect(s.wardNo, isNotNull, reason: '${s.id} should be auto-assigned a ward');
        expect(s.rings, isNotEmpty);
        expect(s.point, isNotNull);
      }
      expect(sites.firstWhere((s) => s.id == 'site-2').onOfficialRecord, isTrue);
      expect(sites.firstWhere((s) => s.id == 'site-1').onOfficialRecord, isFalse);
    });

    test('timeline grows over six months', () async {
      final t = await anon.timeline('site-1');
      expect(t.length, 3);
      expect(t.first.detectedOn, DateTime(2026, 4, 14));
      expect(t.last.areaM2! > t.first.areaM2!, isTrue);
      expect(t.first.rings, isNotEmpty);
    });

    test('fires, wards, leaderboard', () async {
      expect((await anon.fires()).length, greaterThanOrEqualTo(3));
      expect((await anon.fires(siteId: 'site-1')).single.frp, 12.5);
      expect((await anon.wards(cityId: 'indore')).length, 2);
      final board = await anon.leaderboard();
      expect(board.length, 4);
      expect(board.first.rank, 1);
    });

    test('anon cannot file a report', () async {
      await expectLater(anon.submitReport(lat: 22.65, lng: 75.8), throwsA(isA<PostgrestException>()));
    });
  });

  late String nearReport;
  late String farReport;

  group('citizen', skip: !_live, () {
    test('profile is a citizen', () async {
      expect((await citizen.myProfile())!.role, 'citizen');
    });

    test('uploads a photo and files a report matched to site-1', () async {
      final path = await citizen.uploadReportPhoto(_photoWithExif());
      expect(path, startsWith('reports/${citizen.user!.id}/'));
      // A-04: private bucket. The reporter and staff get a signed URL; the public does not.
      final mine = await http.get(Uri.parse((await citizen.photoUrl(path))!));
      expect(mine.statusCode, 200);
      expect((await http.get(Uri.parse((await officer.photoUrl(path))!))).statusCode, 200);
      await expectLater(anon.photoUrl(path), throwsA(anything));
      // N-12: re-encoded as JPEG with no EXIF.
      final back = img.decodeImage(mine.bodyBytes)!;
      expect(img.JpegDecoder().isValidFile(mine.bodyBytes), isTrue);
      expect(img.decodeJpg(_photoWithExif())!.exif.imageIfd['Make'], isNotNull, reason: 'the original has EXIF');
      expect(back.exif.imageIfd['Make'], isNull);
      expect(back.exif.isEmpty, isTrue);
      final res = await citizen.submitReport(lat: 22.6503, lng: 75.8005, note: 'E2E near site-1', photoUrl: path);
      expect(res['status'], 'matched');
      expect(res['site_id'], 'site-1');
      expect(res['distance_m'] as num, lessThan(150));
      nearReport = res['id'] as String;
    });

    test('a report far from any site is flagged for review', () async {
      final res = await citizen.submitReport(lat: 22.79, lng: 75.95, note: 'E2E new place');
      expect(res['status'], 'flagged_for_review');
      farReport = res['id'] as String;
    });

    test('sees own reports only', () async {
      final mine = await citizen.myReports();
      expect(mine.map((r) => r.id), containsAll([nearReport, farReport]));
      expect(mine.firstWhere((r) => r.id == nearReport).photoUrl, isNotNull);
      expect((await anon.allReports()), isEmpty);
    });

    test('cannot act as an officer', () async {
      await expectLater(citizen.insertComplaint(siteId: 'site-1', text: 'x', language: 'English'),
          throwsA(isA<PostgrestException>()));
      await citizen.updateSite('site-2', {'status': 'dismissed'});
      expect((await anon.site('site-2'))!.status, 'active', reason: 'RLS must ignore a citizen update');
      await expectLater(citizen.queueRun(cityId: 'indore', kind: 'detect'), throwsA(isA<PostgrestException>()));
    });

    test('edits own profile but not own role', () async {
      await citizen.updateMyProfile(language: 'Hindi');
      expect((await citizen.myProfile())!.language, 'Hindi');
      await citizen.updateMyProfile(language: 'English');
      await expectLater(citizen.db.from('profiles').update({'role': 'admin'}).eq('user_id', citizen.user!.id),
          throwsA(isA<PostgrestException>()));
    });
  });

  group('officer workflow (no API: template drafting)', skip: !_live, () {
    late ActionEngine engine;
    setUpAll(() => engine = _local(officer));

    test('sees every site including the low-confidence one', () async {
      expect((await officer.myProfile())!.canAct, isTrue);
      expect((await officer.sites()).map((s) => s.id), contains('site-4'));
    });

    test('draft -> approve -> send -> verify -> close', () async {
      final site = (await officer.site('site-1'))!;
      var c = await engine.draftComplaint(site, language: 'English');
      expect(c.status, 'draft');
      expect(c.wardId, 'w-ind-12', reason: 'ward filled from the site by the trigger');
      expect(c.draftText, contains('Ward 12 (Rau)'));
      expect((await anon.complaints(siteId: 'site-1')).map((x) => x.id), isNot(contains(c.id)),
          reason: 'drafts are not public');

      c = await engine.saveText(c, '${c.draftText}\n(E2E edit)');
      expect(c.draftText, endsWith('(E2E edit)'));
      c = await engine.approve(c);
      expect(c.status, 'approved');
      expect(c.approvedBy, officer.user!.id);
      c = await engine.send(c, site);
      expect(c.status, 'sent');
      expect(c.sentAt, isNotNull);
      expect(ActionEngine.mailto(c, site).path, 'ward12.indore@example.com');
      expect((await anon.site('site-1'))!.status, 'complaint_sent');
      expect((await anon.complaints(siteId: 'site-1')).map((x) => x.id), contains(c.id),
          reason: 'sent complaints are public');

      expect(await engine.verifyAll(), greaterThanOrEqualTo(1));
      expect((await anon.verifications('site-1')).first.result, 'still_present');

      c = await engine.close(c);
      expect(c.status, 'closed');
    });

    test('Hindi draft', () async {
      final c = await engine.draftComplaint((await officer.site('site-3'))!, language: 'Hindi');
      expect(c.language, 'Hindi');
      expect(c.draftText, contains('वार्ड अधिकारी'));
    });

    test('verifying a site that B flagged as gone clears it', () async {
      await officer.updateSite('site-5', {'status': 'complaint_sent'});
      await officer.db.from('sites').update({'cleared_candidate': true}).eq('id', 'site-5');
      final site = (await officer.site('site-5'))!;
      expect(await engine.verifySite(site), 'cleared');
      final after = (await anon.site('site-5'))!;
      expect(after.status, 'cleared');
    });

    test('recomputes the city score', () async {
      await engine.refreshScore('indore');
      final indore = (await anon.leaderboard()).firstWhere((s) => s.cityId == 'indore');
      expect(indore.period, isNot('2026-09'));
      expect(indore.parts.keys, containsAll(['active', 'burn', 'clear_time', 'verified']));
    });

    test('queues a run for B and reviews reports', () async {
      await engine.queueRun('indore', 'fires');
      final runs = await officer.runs();
      expect(runs.first.status, 'queued');
      expect(runs.first.kind, 'fires');

      expect((await officer.allReports()).map((r) => r.id), containsAll([nearReport, farReport]));
      await officer.reviewReport(farReport, status: 'rejected');
      expect((await citizen.myReports()).firstWhere((r) => r.id == farReport).status, 'rejected');

      final audit = await officer.db.from('audit_log').select().eq('actor', officer.user!.id);
      expect(audit.map((a) => a['action']), containsAll(['draft', 'approve', 'send', 'verify', 'close']));
    });

    test('a board member can read but not act', () async {
      await admin.setUserRole(citizen.user!.id, 'board');
      final p = (await admin.profiles()).firstWhere((x) => x.userId == citizen.user!.id);
      expect(p.role, 'board');
      expect((await citizen.allReports()).length, greaterThanOrEqualTo(2), reason: 'board can read all reports');
      await expectLater(citizen.insertComplaint(siteId: 'site-1', text: 'x', language: 'English'),
          throwsA(isA<PostgrestException>()));
      await admin.setUserRole(citizen.user!.id, 'citizen');
    });

    test('only an admin changes roles', () async {
      await expectLater(officer.setUserRole(citizen.user!.id, 'admin'), throwsA(isA<PostgrestException>()));
    });

    test('put the demo sites back', () async {
      await officer.updateSite('site-1', {'status': 'active'});
      await officer.updateSite('site-5', {'status': 'active', 'cleared_candidate': false, 'cleared_at': null});
      expect((await anon.site('site-1'))!.status, 'active');
    });
  });

  group('Member A requirements (A-06, A-07, A-16, A-18, A-20, A-22)', skip: !_live, () {
    late ActionEngine engine;
    setUpAll(() => engine = _local(officer));

    test('A-06: a site change reaches an open map within 5 s', () async {
      final got = Completer<void>();
      final joined = Completer<void>();
      final channel = anon.db
          .channel('e2e-${DateTime.now().microsecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'sites',
            callback: (p) {
              if (p.newRecord['id'] == 'site-2' && !got.isCompleted) got.complete();
            },
          )
          .subscribe((status, _) {
        if (status == RealtimeSubscribeStatus.subscribed && !joined.isCompleted) joined.complete();
      });
      await joined.future.timeout(const Duration(seconds: 15));
      final sw = Stopwatch()..start();
      await officer.updateSite('site-2', {'status': 'cleanup_reported'});
      await got.future.timeout(const Duration(seconds: 5));
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      await anon.db.removeChannel(channel);
    });

    test('A-07: the database audits every status change', () async {
      await officer.updateSite('site-2', {'status': 'active'});
      final rows = await officer.db
          .from('audit_log')
          .select()
          .eq('action', 'status_change')
          .eq('entity_id', 'site-2')
          .order('at', ascending: false);
      expect(rows.first['details'], {'from': 'cleanup_reported', 'to': 'active'});
      expect(rows.first['actor'], officer.user!.id);
    });

    test('A-16: dismiss with a reason hides the site from the public', () async {
      await engine.dismiss((await officer.site('site-2'))!, 'E2E: construction site');
      expect((await anon.site('site-2')), isNull);
      final s = (await officer.site('site-2'))!;
      expect(s.status, 'dismissed');
      expect(s.dismissedReason, 'E2E: construction site');
      final audit = await officer.db.from('audit_log').select().eq('entity_id', 'site-2').order('at', ascending: false);
      expect((audit.first['details'] as Map)['reason'], 'E2E: construction site');
      await officer.updateSite('site-2', {'status': 'active', 'dismissed_reason': null});
    });

    test('A-22: new detections wait for review', () async {
      expect((await officer.unreviewedSites()).map((x) => x.id), contains('site-4'));
      await officer.markReviewed('site-4');
      expect((await officer.unreviewedSites()).map((x) => x.id), isNot(contains('site-4')));
      await officer.updateSite('site-4', {'reviewed_at': null, 'reviewed_by': null});
    });

    test('A-18: admins set the home city of an officer', () async {
      await admin.setUserAccess(officer.user!.id, 'officer', 'indore');
      expect((await officer.myProfile())!.cityId, 'indore');
      await expectLater(officer.setUserAccess(officer.user!.id, 'admin', null), throwsA(isA<PostgrestException>()));
      await admin.setUserAccess(officer.user!.id, 'officer', null);
    });

    test('A-20: monthly score history, oldest first', () async {
      final months = await anon.scoreHistory('indore');
      expect(months.length, greaterThanOrEqualTo(5));
      expect(months.first.$1.compareTo(months.last.$1), lessThan(0));
    });

    test('A-15: timeline through the action engine', () async {
      final t = await engine.timeline('site-1');
      expect(t.length, 3);
      expect(t.first.rings, isNotEmpty);
    });
  });
}
