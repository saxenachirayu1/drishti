import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => 'API $status: $message';
}

/// Member C's FastAPI service (api/). Only used when API_BASE_URL is set.
class DrishtiApi {
  DrishtiApi(this.baseUrl, this.token, {http.Client? client}) : _http = client ?? http.Client();

  final String baseUrl;
  final String? Function() token;
  final http.Client _http;

  bool get enabled => baseUrl.isNotEmpty;

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    if (token() != null) 'authorization': 'Bearer ${token()}',
  };

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final uri = Uri.parse('$baseUrl$path');
    final req = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 60)));
    final decoded = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      final msg = decoded is Map && decoded['error'] is Map
          ? decoded['error']['message']?.toString()
          : decoded is Map
          ? decoded['detail']?.toString()
          : null;
      throw ApiException(res.statusCode, msg ?? res.reasonPhrase ?? 'request failed');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> health() async => Map<String, dynamic>.from(await _send('GET', '/health'));

  /// [{detection_id, date, area_m2, confidence, thumb_url}] in date order.
  Future<List<Map<String, dynamic>>> timeline(String siteId) async => [
    for (final r in await _send('GET', '/sites/$siteId/timeline') as List) Map<String, dynamic>.from(r as Map),
  ];

  Future<void> dismissSite(String siteId, String reason) => _send('POST', '/sites/$siteId/dismiss', {'reason': reason});

  Future<Map<String, dynamic>> createComplaint(String siteId, String language) async =>
      Map<String, dynamic>.from(await _send('POST', '/complaints', {'site_id': siteId, 'language': language}));

  Future<void> editComplaint(String id, String text) => _send('PATCH', '/complaints/$id', {'draft_text': text});

  Future<void> approveComplaint(String id) => _send('POST', '/complaints/$id/approve');

  Future<void> sendComplaint(String id) => _send('POST', '/complaints/$id/send');

  Future<Map<String, dynamic>> chat(String message, {String? cityId, required String language}) async =>
      Map<String, dynamic>.from(
        await _send('POST', '/assistant/chat', {'message': message, 'city_id': cityId, 'language': language}),
      );

  Future<void> cityScore(String cityId) => _send('GET', '/cities/$cityId/score');

  Future<Map<String, dynamic>> runVerification() async =>
      Map<String, dynamic>.from(await _send('POST', '/verifications/run'));

  Future<Map<String, dynamic>> runPipeline(String cityId, String dateFrom, String dateTo) async =>
      Map<String, dynamic>.from(
        await _send('POST', '/pipeline/run', {'city_id': cityId, 'date_from': dateFrom, 'date_to': dateTo}),
      );
}
