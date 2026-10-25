import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/action.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import '../services/action_engine.dart';
import '../widgets/common.dart';
import 'site_detail_screen.dart';

/// One complaint through its life: draft (editable) -> approved -> sent -> closed.
class ComplaintScreen extends ConsumerStatefulWidget {
  const ComplaintScreen({super.key, required this.complaintId});
  final String complaintId;

  @override
  ConsumerState<ComplaintScreen> createState() => _ComplaintScreenState();
}

class _ComplaintScreenState extends ConsumerState<ComplaintScreen> {
  final _text = TextEditingController();
  String? _loadedFor;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _refresh(Complaint c) {
    ref.invalidate(complaintProvider(widget.complaintId));
    ref.invalidate(siteComplaintsProvider(c.siteId));
    ref.invalidate(allComplaintsProvider);
    ref.invalidate(sitesProvider);
  }

  Future<void> _run(Complaint c, Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    final ok = await guarded(context, action, success: success);
    if (mounted) setState(() => _busy = false);
    if (ok) _refresh(c);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final canAct = ref.watch(profileProvider).value?.canAct ?? false;
    final actions = ref.read(actionsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.complaint)),
      body: AsyncView(ref.watch(complaintProvider(widget.complaintId)), builder: (c) {
        if (c == null) return const Center(child: EmptyNote());
        final key = '${c.id}:${c.status}:${c.draftText.hashCode}';
        if (_loadedFor != key) {
          _loadedFor = key;
          _text.text = c.draftText;
        }
        final editable = canAct && c.status == 'draft';
        const steps = ['draft', 'approved', 'sent', 'closed'];
        final step = steps.indexOf(c.status);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(padding: const EdgeInsets.all(12), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    for (var i = 0; i < steps.length; i++) ...[
                      Icon(i <= step ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: i <= step ? statusColor(steps[i]) : Colors.grey, size: 20),
                      const SizedBox(width: 4),
                      Flexible(child: Text(s.status(steps[i]), overflow: TextOverflow.ellipsis)),
                      if (i < steps.length - 1) const Expanded(child: Divider(indent: 6, endIndent: 6)),
                    ],
                  ]),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    InfoRow(s.site, c.siteId),
                    InfoRow(s.language, c.language),
                    if (c.sentAt != null) InfoRow(s.status('sent'), fmtDateTime(c.sentAt)),
                    if (c.closedAt != null) InfoRow(s.status('closed'), fmtDateTime(c.closedAt)),
                    TextButton(
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => SiteDetailScreen(siteId: c.siteId))),
                      child: Text('${s.open} ${s.site.toLowerCase()} ${c.siteId}'),
                    ),
                  ]),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _text,
                    readOnly: !editable,
                    maxLines: null,
                    minLines: 12,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: const InputDecoration(border: InputBorder.none),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy),
                  label: Text(s.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: c.draftText));
                    if (context.mounted) toast(context, s.copied);
                  },
                ),
                if (c.pdfUrl != null && c.pdfUrl!.startsWith('http'))
                  OutlinedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf),
                    label: Text(s.openPdf),
                    onPressed: () => launchUrl(Uri.parse(c.pdfUrl!)),
                  ),
                if (editable) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.save),
                    label: Text(s.save),
                    onPressed: _busy ? null : () => _run(c, () => actions.saveText(c, _text.text), success: s.saved),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.verified),
                    label: Text(s.approve),
                    onPressed: _busy
                        ? null
                        : () => _run(c, () async {
                              if (_text.text != c.draftText) await actions.saveText(c, _text.text);
                              final latest = await ref.read(repoProvider).complaint(c.id);
                              await actions.approve(latest ?? c);
                            }),
                  ),
                ],
                if (canAct && c.status == 'approved')
                  FilledButton.icon(
                    icon: const Icon(Icons.send),
                    label: Text(s.send),
                    onPressed: _busy
                        ? null
                        : () => _run(c, () async {
                              final site = await ref.read(repoProvider).site(c.siteId);
                              if (site == null) throw StateError('Site ${c.siteId} not found');
                              final sent = await actions.send(c, site);
                              if (!actions.usesApi) {
                                await launchUrl(ActionEngine.mailto(sent, site));
                                if (mounted) toast(this.context, s.emailOpened);
                              }
                            }),
                  ),
                if (canAct && c.status == 'sent')
                  OutlinedButton.icon(
                    icon: const Icon(Icons.task_alt),
                    label: Text(s.closeComplaint),
                    onPressed: _busy ? null : () => _run(c, () => actions.close(c)),
                  ),
              ]),
            ]),
          ),
        );
      }),
    );
  }
}
