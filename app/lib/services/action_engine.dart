import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/action.dart';
import '../models/place.dart';
import '../models/site.dart';
import 'api_client.dart';
import 'complaint_drafter.dart';
import 'drishti_repo.dart';
import 'local_assistant.dart';
import 'verification_logic.dart';

/// The officer workflow: draft -> approve -> send -> verify, plus scores,
/// pipeline runs and the assistant.
///
/// When Member C's API is configured, it does the work (Granite drafting, PDF,
/// email). If the API is not configured or cannot be reached, the same step is
/// done directly against Supabase, so every feature works either way.
class ActionEngine {
  ActionEngine(this.repo, this.api);

  final DrishtiRepo repo;
  final DrishtiApi api;

  bool get usesApi => api.enabled;

  Future<T> _apiOr<T>(Future<T> Function() viaApi, Future<T> Function() local) async {
    if (!api.enabled) return local();
    try {
      return await viaApi();
    } on http.ClientException {
      return local();
    } on TimeoutException {
      return local();
    }
  }

  // --- complaints ------------------------------------------------------------

  Future<Complaint> draftComplaint(Site site, {City? city, required String language}) => _apiOr(
    () async {
      final c = await api.createComplaint(site.id, language);
      return (await repo.complaint(c['id'] as String)) ?? Complaint.fromMap(c);
    },
    () async {
      final text = ComplaintDrafter.draft(site, city: city, language: language);
      final c = await repo.insertComplaint(siteId: site.id, text: text, language: language);
      await repo.audit('draft', 'complaint', c.id, {'site_id': site.id, 'language': language});
      return c;
    },
  );

  Future<Complaint> saveText(Complaint c, String text) => _apiOr(() async {
    await api.editComplaint(c.id, text);
    return (await repo.complaint(c.id))!;
  }, () => repo.updateComplaint(c.id, {'draft_text': text}));

  Future<Complaint> approve(Complaint c) => _apiOr(
    () async {
      await api.approveComplaint(c.id);
      return (await repo.complaint(c.id))!;
    },
    () async {
      final out = await repo.updateComplaint(c.id, {'status': 'approved', 'approved_by': repo.user?.id});
      await repo.audit('approve', 'complaint', c.id);
      return out;
    },
  );

  /// Marks the complaint sent and the site complaint_sent. Through the API the
  /// officer is emailed by the server; locally the caller opens [mailto].
  Future<Complaint> send(Complaint c, Site site) => _apiOr(
    () async {
      await api.sendComplaint(c.id);
      return (await repo.complaint(c.id))!;
    },
    () async {
      if (c.status != 'approved') throw StateError('Approve the complaint before sending');
      final out = await repo.updateComplaint(c.id, {
        'status': 'sent',
        'sent_at': DateTime.now().toUtc().toIso8601String(),
      });
      await repo.updateSite(site.id, {'status': 'complaint_sent'});
      await repo.audit('send', 'complaint', c.id, {'to': site.officerEmail});
      return out;
    },
  );

  Future<Complaint> close(Complaint c) async {
    final out = await repo.updateComplaint(c.id, {
      'status': 'closed',
      'closed_at': DateTime.now().toUtc().toIso8601String(),
    });
    await repo.audit('close', 'complaint', c.id);
    return out;
  }

  static Uri mailto(Complaint c, Site site) => Uri(
    scheme: 'mailto',
    path: site.officerEmail ?? '',
    query: _query({
      'subject': c.language == 'Hindi'
          ? 'संदिग्ध अवैध कचरा स्थल - कार्रवाई का अनुरोध (${site.id})'
          : 'Suspected illegal dumpsite - action requested (${site.id})',
      'body': c.draftText,
    }),
  );

  static String _query(Map<String, String> p) =>
      p.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

  // --- site status and verification -------------------------------------------

  /// The before/after slider's data (A-15): GET /sites/{id}/timeline when the
  /// API is up, with each detection's outline from the database.
  Future<List<Detection>> timeline(String siteId) async {
    final rows = await repo.timeline(siteId);
    if (!api.enabled) return rows;
    try {
      final byId = {for (final d in rows) d.id: d};
      return [
        for (final r in await api.timeline(siteId))
          Detection(
            id: r['detection_id'] as String,
            siteId: siteId,
            detectedOn: DateTime.tryParse('${r['date']}'),
            areaM2: (r['area_m2'] as num?)?.toDouble(),
            confidence: (r['confidence'] as num?)?.toDouble(),
            thumbUrl: r['thumb_url'] as String? ?? byId[r['detection_id']]?.thumbUrl,
            rings: byId[r['detection_id']]?.rings ?? const [],
          ),
      ];
    } on http.ClientException {
      return rows;
    } on TimeoutException {
      return rows;
    }
  }

  /// Marks a false positive (A-16). The site leaves the public map and the
  /// reason is kept on the site and in the audit log for retraining.
  Future<void> dismiss(Site site, String reason) async {
    await _apiOr(() => api.dismissSite(site.id, reason), () async {});
    await repo.updateSite(site.id, {'status': 'dismissed', 'dismissed_reason': reason});
  }

  /// The database trigger writes the audit row (A-07).
  Future<void> setSiteStatus(Site site, String status) => repo.updateSite(site.id, {'status': status});

  /// Checks one site's detection history and records the result (C-12).
  Future<String> verifySite(Site site, {String? complaintId}) async {
    final dets = await repo.timeline(site.id);
    final areas = [for (final d in dets) d.areaM2 ?? 0];
    // B's pipeline flags a site that is missing from two clear scenes.
    if (site.clearedCandidate) areas.addAll([0, 0]);
    final result = decideResult(areas);
    await repo.addVerification(
      siteId: site.id,
      result: result,
      complaintId: complaintId,
      evidenceDetectionId: dets.isEmpty ? null : dets.last.id,
    );
    if (result == 'cleared' && site.status != 'cleared') {
      await repo.updateSite(site.id, {'status': 'cleared'});
    }
    await repo.audit('verify', 'site', site.id, {'result': result});
    return result;
  }

  /// Verifies every site with a sent complaint. Returns how many were checked.
  Future<int> verifyAll() => _apiOr(() async => ((await api.runVerification())['checked'] as num).toInt(), () async {
    final sites = (await repo.sites()).where((s) => s.status == 'complaint_sent').toList();
    for (final s in sites) {
      await verifySite(s);
    }
    return sites.length;
  });

  // --- scores and pipeline ------------------------------------------------------

  Future<void> refreshScore(String cityId) => _apiOr(() => api.cityScore(cityId), () => repo.refreshScore(cityId));

  /// Queues a run for B's worker. kind is 'detect' (satellite scenes) or 'fires' (NASA FIRMS).
  Future<void> queueRun(String cityId, String kind, {int days = 10}) async {
    final f = DateFormat('yyyy-MM-dd');
    final end = DateTime.now();
    final start = end.subtract(Duration(days: days));
    if (api.enabled && kind == 'detect') {
      try {
        await api.runPipeline(cityId, f.format(start), f.format(end));
        return;
      } on http.ClientException {
        // fall through to queueing directly
      } on TimeoutException {
        // fall through to queueing directly
      }
    }
    await repo.queueRun(cityId: cityId, kind: kind, params: {'start': f.format(start), 'end': f.format(end)});
    await repo.audit('queue_run', 'pipeline_run', cityId, {'kind': kind});
  }

  // --- assistant ------------------------------------------------------------------

  Future<AssistantReply> ask(String question, {String? cityId, required bool hindi}) => _apiOr(
    () async {
      final r = await api.chat(question, cityId: cityId, language: hindi ? 'Hindi' : 'English');
      return AssistantReply(
        r['answer'] as String,
        siteIds: [for (final id in (r['site_ids'] as List? ?? const [])) id as String],
        tool: (r['tools_used'] as List?)?.join(', '),
      );
    },
    () async => LocalAssistant.answer(
      question,
      sites: await repo.sites(),
      cities: await repo.cities(),
      scores: await repo.leaderboard(),
      cityId: cityId,
      hindi: hindi,
    ),
  );
}
