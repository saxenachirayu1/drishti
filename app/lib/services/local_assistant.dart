import '../models/place.dart';
import '../models/site.dart';

class AssistantReply {
  const AssistantReply(this.answer, {this.siteIds = const [], this.tool});
  final String answer;
  final List<String> siteIds;
  final String? tool;
}

/// Answers from the map data when Member C's Granite assistant is not running.
/// Same fixed, read-only tools and guardrails as api/app/services/assistant_tools.py,
/// plus Hindi keywords.
class LocalAssistant {
  static const _onTopic = [
    'site',
    'dump',
    'waste',
    'garbage',
    'ward',
    'fire',
    'burn',
    'city',
    'river',
    'water',
    'lake',
    'clean',
    'score',
    'complaint',
    'how many',
    'कचरा',
    'डंप',
    'साइट',
    'वार्ड',
    'आग',
    'जल',
    'पानी',
    'नदी',
    'शहर',
    'स्कोर',
    'शिकायत',
    'कितने',
    'सफाई',
  ];
  static const _injection = [
    'ignore previous',
    'ignore the above',
    'system prompt',
    'reveal',
    'api key',
    'password',
    'secret',
  ];

  static AssistantReply answer(
    String question, {
    required List<Site> sites,
    required List<City> cities,
    List<CityScore> scores = const [],
    String? cityId,
    bool hindi = false,
  }) {
    final q = question.toLowerCase();
    String t(String en, String hi) => hindi ? hi : en;

    if (_injection.any(q.contains)) {
      return AssistantReply(
        t(
          'I can only answer questions about dumpsites, wards, fires and city scores.',
          'मैं केवल कचरा स्थलों, वार्डों, आग और शहर के स्कोर के बारे में जवाब दे सकता हूँ।',
        ),
      );
    }
    if (!_onTopic.any(q.contains)) {
      return AssistantReply(
        t(
          "I can only help with Drishti's dumpsite, ward, fire and city-score data.",
          'मैं केवल Drishti के कचरा स्थल, वार्ड, आग और शहर-स्कोर डेटा में मदद कर सकता हूँ।',
        ),
      );
    }

    final named = cityId ?? _cityIn(q, cities);
    final scoped = named == null ? sites : sites.where((s) => s.cityId == named).toList();
    final live = scoped.where((s) => s.status != 'dismissed').toList();
    String cityName(String id) => cities.where((c) => c.id == id).map((c) => c.name).firstOrNull ?? id;
    String label(Site s) =>
        '${cityName(s.cityId)} ${t('ward', 'वार्ड')} ${s.wardNo ?? '?'}'
        ' (${s.areaM2.round()} m²)';

    AssistantReply listOf(String tool, List<Site> rows, String en, String hi) {
      if (rows.isEmpty)
        return AssistantReply(
          t('No records match that question.', 'इस प्रश्न से मेल खाता कोई रिकॉर्ड नहीं है।'),
          tool: tool,
        );
      return AssistantReply(
        '${t(en, hi)} ${rows.map(label).join(', ')}.',
        siteIds: [for (final s in rows) s.id],
        tool: tool,
      );
    }

    if (q.contains('fire') || q.contains('burn') || q.contains('आग')) {
      return listOf(
        'search_sites(fire)',
        live.where((s) => s.highFireRisk).toList(),
        'Sites with high fire risk:',
        'अधिक आग जोखिम वाले स्थल:',
      );
    }
    if (q.contains('river') ||
        q.contains('water') ||
        q.contains('lake') ||
        q.contains('नदी') ||
        q.contains('पानी') ||
        q.contains('जल')) {
      return listOf(
        'search_sites(near_water)',
        live.where((s) => s.nearWater).toList(),
        'Sites near water:',
        'जल स्रोत के पास स्थल:',
      );
    }
    if (q.contains('score') || q.contains('स्कोर') || q.contains('clean') || q.contains('सफाई')) {
      final rows = named == null ? scores : scores.where((s) => s.cityId == named).toList();
      if (rows.isEmpty) return AssistantReply(t('No score yet.', 'अभी कोई स्कोर नहीं है।'), tool: 'city_score');
      return AssistantReply(
        rows.map((s) => '${s.name}: ${s.score}/100 (#${s.rank}, ${s.period})').join('; '),
        tool: 'city_score',
      );
    }
    if (q.contains('how many') || q.contains('count') || q.contains('stats') || q.contains('कितने')) {
      if (named == null) {
        final per = cities.map(
          (c) => '${c.name}: ${sites.where((s) => s.cityId == c.id && s.status == 'active').length}',
        );
        return AssistantReply(
          '${t('Active sites by city -', 'शहर के अनुसार सक्रिय स्थल -')} ${per.join(', ')}.',
          tool: 'city_stats',
        );
      }
      final active = scoped.where((s) => s.status == 'active').toList();
      final water = active.where((s) => s.nearWater).length;
      return AssistantReply(
        t(
          '${cityName(named)}: ${scoped.length} sites on record, ${active.length} still active, $water of those near water.',
          '${cityName(named)}: रिकॉर्ड में ${scoped.length} स्थल, ${active.length} अभी सक्रिय, उनमें से $water जल स्रोत के पास।',
        ),
        siteIds: [for (final s in active) s.id],
        tool: 'city_stats',
      );
    }
    if ((q.contains('ward') || q.contains('वार्ड')) &&
        (q.contains('most') || q.contains('rank') || q.contains('worst') || q.contains('सबसे'))) {
      final byWard = <String, int>{};
      for (final s in live) {
        final key = '${cityName(s.cityId)} ${t('ward', 'वार्ड')} ${s.wardNo ?? '?'}';
        byWard[key] = (byWard[key] ?? 0) + 1;
      }
      final ranked = byWard.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      if (ranked.isEmpty)
        return AssistantReply(
          t('No records match that question.', 'इस प्रश्न से मेल खाता कोई रिकॉर्ड नहीं है।'),
          tool: 'ward_ranking',
        );
      return AssistantReply(
        '${t('Sites per ward, most first -', 'वार्ड के अनुसार स्थल, सबसे अधिक पहले -')} '
        '${ranked.map((e) => '${e.key}: ${e.value}').join(', ')}.',
        tool: 'ward_ranking',
      );
    }
    return listOf('search_sites', live, 'Matching sites:', 'मिलते-जुलते स्थल:');
  }

  static String? _cityIn(String q, List<City> cities) {
    const hindiNames = {'इंदौर': 'indore', 'भोपाल': 'bhopal', 'पुणे': 'pune', 'दिल्ली': 'delhi'};
    for (final c in cities) {
      if (q.contains(c.id.toLowerCase()) || q.contains(c.name.toLowerCase())) return c.id;
    }
    for (final e in hindiNames.entries) {
      if (q.contains(e.key)) {
        final match = cities.where((c) => c.name.toLowerCase() == e.value);
        if (match.isNotEmpty) return match.first.id;
      }
    }
    return null;
  }
}
