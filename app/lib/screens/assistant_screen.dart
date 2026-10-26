import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/place.dart';
import '../providers.dart';
import '../services/local_assistant.dart';
import 'site_detail_screen.dart';

/// Ask the map in plain English or Hindi.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _Msg {
  const _Msg(this.text, {this.fromUser = false, this.siteIds = const []});
  final String text;
  final bool fromUser;
  final List<String> siteIds;
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Msg>[];
  String? _cityId;
  bool _busy = false;

  static const _suggestEn = [
    'Which sites are near water?',
    'Which sites have high fire risk?',
    'Which ward has the most dumps in Indore?',
    'How many sites in Bhopal?',
    'What is the cleanliness score?',
  ];
  static const _suggestHi = [
    'कौन से स्थल पानी के पास हैं?',
    'किन स्थलों पर आग का जोखिम है?',
    'इंदौर में किस वार्ड में सबसे अधिक कचरा है?',
    'भोपाल में कितने स्थल हैं?',
    'स्वच्छता स्कोर क्या है?',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask(String q) async {
    if (q.trim().isEmpty) return;
    final hindi = ref.read(hindiProvider);
    setState(() {
      _messages.add(_Msg(q, fromUser: true));
      _busy = true;
      _input.clear();
    });
    AssistantReply reply;
    try {
      reply = await ref.read(actionsProvider).ask(q, cityId: _cityId, hindi: hindi);
    } catch (e) {
      reply = AssistantReply('$e');
    }
    if (!mounted) return;
    setState(() {
      _messages.add(_Msg(reply.answer, siteIds: reply.siteIds));
      _busy = false;
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final hindi = ref.watch(hindiProvider);
    final cities = ref.watch(citiesProvider).value ?? const <City>[];
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(children: [
              Expanded(child: Text(s.assistantHint, style: Theme.of(context).textTheme.bodySmall)),
              DropdownButton<String?>(
                value: _cityId,
                items: [
                  DropdownMenuItem(value: null, child: Text(s.anyCity)),
                  for (final c in cities) DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _cityId = v),
              ),
            ]),
          ),
          Expanded(
            child: ListView(controller: _scroll, padding: const EdgeInsets.all(12), children: [
              if (_messages.isEmpty)
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final q in hindi ? _suggestHi : _suggestEn) ActionChip(label: Text(q), onPressed: () => _ask(q)),
                ]),
              for (final m in _messages)
                Align(
                  alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 600),
                    decoration: BoxDecoration(
                      color: m.fromUser ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SelectableText(m.text),
                      if (m.siteIds.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.map, size: 16),
                            label: Text(s.showOnMap),
                            onPressed: () {
                              ref.read(highlightProvider.notifier).set(m.siteIds);
                              ref.read(tabRequestProvider.notifier).set('map');
                            },
                          ),
                          for (final id in m.siteIds)
                            ActionChip(
                              avatar: const Icon(Icons.location_on, size: 16),
                              label: Text(id),
                              onPressed: () => Navigator.push(
                                  context, MaterialPageRoute(builder: (_) => SiteDetailScreen(siteId: id))),
                            ),
                        ]),
                      ],
                    ]),
                  ),
                ),
              if (_busy) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
            ]),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _ask,
                    decoration: InputDecoration(hintText: s.askAnything, border: const OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                    icon: const Icon(Icons.send), onPressed: _busy ? null : () => _ask(_input.text)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
