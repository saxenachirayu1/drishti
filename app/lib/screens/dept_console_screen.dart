import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../complaints_providers.dart';
import '../models/ticket.dart';
import '../services/tracking_logic.dart';
import '../theme/d_strings.dart';
import '../theme/drishti_theme.dart';
import '../widgets/common.dart';
import '../widgets/d_widgets.dart';
import 'site_detail_screen.dart';
import 'track_screen.dart';

enum QueueFilter { open, overdue, burning, closed }

/// Which complaints a filter keeps.
bool queueFilterKeeps(QueueFilter f, Ticket t, DateTime now) => switch (f) {
  QueueFilter.open => !t.isClosed,
  QueueFilter.overdue => !t.isClosed && replyClock(t, now) is Overdue,
  QueueFilter.burning => !t.isClosed && t.category == 'burning',
  QueueFilter.closed => t.isClosed,
};

/// The department console: a queue ordered by what is late, and one place to
/// post the update the resident will see. Officers and admins post; the
/// pollution control board reads.
class DeptConsoleScreen extends ConsumerStatefulWidget {
  const DeptConsoleScreen({super.key, this.canAct = true, this.department});
  final bool canAct;

  /// The officer's own department; null shows all.
  final String? department;

  @override
  ConsumerState<DeptConsoleScreen> createState() => _DeptConsoleScreenState();
}

class _DeptConsoleScreenState extends ConsumerState<DeptConsoleScreen> {
  late String? _dept = widget.department;
  QueueFilter _filter = QueueFilter.open;
  String? _selected;

  void _open(Ticket t) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    setState(() => _selected = t.id);
    if (!wide) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Consumer(
            builder: (context, ref, _) {
              return Scaffold(
                appBar: AppBar(title: Text(t.ticket ?? ref.watch(dsProvider).consoleTitle)),
                body: ComplaintWorkspace(reportId: t.id, canAct: widget.canAct),
              );
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = ref.watch(dsProvider);
    final t = DText(ds.hindi);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final queue = ref.watch(queueProvider(_dept));
    final all = queue.value ?? const <Ticket>[];
    final open = all.where((x) => !x.isClosed).toList();
    final overdue = open.where((x) => replyClock(x, now) is Overdue).length;
    final answered = all.where((x) => x.firstReplyAt != null || replyClock(x, now) is Overdue).toList();
    final onTime = answered.isEmpty
        ? null
        : (100 *
                  answered.where((x) {
                    final c = replyClock(x, now);
                    return c is Replied && c.onTime;
                  }).length /
                  answered.length)
              .round();

    final top = Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        color: DColors.surface,
        border: Border(bottom: BorderSide(color: DColors.rule)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(ds.consoleTitle, style: t.head(22)),
              DropdownButton<String?>(
                key: const ValueKey('dept-select'),
                value: _dept,
                underline: const SizedBox.shrink(),
                style: t.body(14, weight: FontWeight.w600),
                items: [
                  DropdownMenuItem(value: null, child: Text(ds.allDepts)),
                  for (final d in const ['swm', 'pwd', 'cnd']) DropdownMenuItem(value: d, child: Text(ds.deptName(d))),
                ],
                onChanged: (v) => setState(() {
                  _dept = v;
                  _selected = null;
                }),
              ),
            ],
          ),
          Wrap(
            spacing: 18,
            children: [
              _Stat(ds.nOverdue(overdue), color: overdue > 0 ? DColors.fire : DColors.ink, hindi: ds.hindi),
              _Stat(ds.nOpen(open.length), hindi: ds.hindi),
              _Stat(ds.onTimeMonth(onTime), color: DColors.clean, hindi: ds.hindi),
            ],
          ),
        ],
      ),
    );

    final counts = {for (final f in QueueFilter.values) f: all.where((x) => queueFilterKeeps(f, x, now)).length};
    String label(QueueFilter f) => switch (f) {
      QueueFilter.open => ds.filterOpen,
      QueueFilter.overdue => ds.filterOverdue,
      QueueFilter.burning => ds.filterBurning,
      QueueFilter.closed => ds.filterClosed,
    };
    final shown = queueOrder(all.where((x) => queueFilterKeeps(_filter, x, now)).toList(), now);

    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in QueueFilter.values)
                ChoiceChip(
                  key: ValueKey('filter-${f.name}'),
                  label: Text('${label(f)} · ${counts[f]}'),
                  selected: _filter == f,
                  showCheckmark: false,
                  selectedColor: DColors.ink,
                  labelStyle: t.body(
                    13,
                    weight: _filter == f ? FontWeight.w600 : FontWeight.w400,
                    color: _filter == f ? DColors.paper : DColors.ink,
                  ),
                  onSelected: (_) => setState(() => _filter = f),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: AsyncView(
            queue,
            onRetry: () => ref.invalidate(queueProvider(_dept)),
            builder: (List<Ticket> _) => shown.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(ds.queueEmpty, style: t.body(14, color: DColors.muted)),
                  )
                : ListView(
                    children: [
                      for (final x in shown)
                        TicketRow(ticket: x, selected: wide && _selected == x.id, onTap: () => _open(x)),
                    ],
                  ),
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        top,
        Expanded(
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 380, child: list),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _selected == null
                          ? Center(
                              child: Text(ds.pickOne, style: t.body(15, color: DColors.muted)),
                            )
                          : ComplaintWorkspace(key: ValueKey(_selected), reportId: _selected!, canAct: widget.canAct),
                    ),
                  ],
                )
              : list,
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.text, {this.color = DColors.ink, required this.hindi});
  final String text;
  final Color color;
  final bool hindi;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: DText(hindi).body(13, weight: FontWeight.w600, color: color),
  );
}

/// One complaint for the department: evidence, the composer, the timeline.
class ComplaintWorkspace extends ConsumerStatefulWidget {
  const ComplaintWorkspace({super.key, required this.reportId, this.canAct = true});
  final String reportId;
  final bool canAct;

  @override
  ConsumerState<ComplaintWorkspace> createState() => _ComplaintWorkspaceState();
}

class _ComplaintWorkspaceState extends ConsumerState<ComplaintWorkspace> {
  final _message = TextEditingController();
  String _stage = 'note';
  Uint8List? _after;
  bool _busy = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _pickAfter() async {
    final file = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (mounted) setState(() => _after = bytes);
  }

  Future<void> _post(DS ds) async {
    final msg = _message.text.trim();
    if (_stage == 'resolved' && _after == null) {
      toast(context, ds.needPhoto);
      return;
    }
    if (_stage == 'note' && msg.isEmpty) {
      toast(context, ds.needMessage);
      return;
    }
    setState(() => _busy = true);
    final ok = await guarded(
      context,
      () => ref
          .read(complaintsApiProvider)
          .postUpdate(widget.reportId, _stage, message: msg.isEmpty ? null : msg, photo: _after),
      success: ds.posted,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _message.clear();
        _after = null;
        _stage = 'note';
      }
    });
    if (ok) {
      ref.invalidate(ticketProvider(widget.reportId));
      ref.invalidate(queueProvider);
    }
  }

  Future<void> _transfer(DS ds, String dept) async {
    final ok = await guarded(
      context,
      () => ref.read(complaintsApiProvider).transfer(widget.reportId, dept),
      success: ds.transferred,
    );
    if (ok) {
      ref.invalidate(ticketProvider(widget.reportId));
      ref.invalidate(queueProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = ref.watch(dsProvider);
    final value = ref.watch(ticketProvider(widget.reportId));
    return AsyncView(
      value,
      onRetry: () => ref.invalidate(ticketProvider(widget.reportId)),
      builder: (Ticket? ticket) {
        if (ticket == null) return Center(child: Text(ds.ticketMissing));
        return _layout(ds, ticket);
      },
    );
  }

  Widget _layout(DS ds, Ticket ticket) {
    final t = DText(ds.hindi);
    final options = nextStages(ticket.stage);
    if (_stage != 'note' && !options.contains(_stage)) _stage = 'note';
    final others = [
      for (final d in const ['swm', 'pwd', 'cnd'])
        if (d != ticket.department) d,
    ];

    final head = Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(ticket.ticket ?? '', style: DText.mono(13, color: DColors.evidence)),
              if (ticket.linkedSiteId != null)
                Text('· ${ds.linkedTo(ticket.linkedSiteId!)}', style: DText.mono(13, color: DColors.muted)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${ds.typeName(ticket.category)}${ticket.locality == null ? '' : ' · ${ticket.locality}'}',
                  style: t.head(26),
                ),
              ),
              if (widget.canAct && others.isNotEmpty)
                PopupMenuButton<String>(
                  key: const ValueKey('transfer'),
                  onSelected: (d) => _transfer(ds, d),
                  itemBuilder: (_) => [
                    for (final d in others) PopupMenuItem(value: d, child: Text(ds.transferTo(ds.deptName(d)))),
                  ],
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFC9CDD6)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(ds.transferTo('…'), style: t.body(13, weight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
          Text('${ds.raisedBy} · ${fmtDateTime(ticket.createdAt)}', style: t.body(13, color: DColors.body)),
          if (ticket.note != null) ...[const SizedBox(height: 8), Text('“${ticket.note}”', style: t.body(15))],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Evidence(
                caption: ds.residentPhoto,
                child: ticket.photoUrl == null
                    ? Center(
                        child: Text(ds.noPhoto, style: t.body(12, color: DColors.muted)),
                      )
                    : ReportPhoto(stored: ticket.photoUrl, size: 180),
              ),
              if (ticket.linkedSiteId != null)
                _Evidence(
                  caption: 'SENTINEL-2 · ${ticket.linkedSiteId}',
                  mono: true,
                  child: InkWell(
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => SiteDetailScreen(siteId: ticket.linkedSiteId!))),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.satellite_alt_outlined),
                          const SizedBox(height: 4),
                          Text(
                            ds.openSite,
                            textAlign: TextAlign.center,
                            style: t.body(12, color: DColors.evidence),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    final composer = !widget.canAct
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
            child: DPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(ds.postUpdate, style: t.body(13, weight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Semantics(
                    label: ds.newStage,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in [...options, 'note'])
                          ChoiceChip(
                            key: ValueKey('stage-$s'),
                            label: Text(s == 'note' ? ds.justNote : '${stageGlyph(s)} ${ds.stamp(s)}'),
                            selected: _stage == s,
                            showCheckmark: false,
                            selectedColor: s == 'resolved' ? DColors.cleanTint : DColors.selected,
                            side: BorderSide(
                              color: _stage == s
                                  ? (s == 'resolved' ? DColors.clean : DColors.ink)
                                  : const Color(0xFFC9CDD6),
                              width: _stage == s ? 2 : 1,
                            ),
                            labelStyle: t.body(
                              13,
                              weight: _stage == s ? FontWeight.w700 : FontWeight.w400,
                              color: s == 'resolved' && _stage == s ? DColors.clean : DColors.ink,
                            ),
                            onSelected: (_) => setState(() => _stage = s),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('dept-message'),
                    controller: _message,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 500,
                    decoration: InputDecoration(labelText: ds.messageLabel),
                  ),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        icon: Icon(_after == null ? Icons.add_a_photo_outlined : Icons.check),
                        label: Text(_after == null ? ds.attachAfter : ds.afterAttached),
                        onPressed: _pickAfter,
                      ),
                      Wrap(
                        spacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(ds.residentSees, style: t.body(12, color: DColors.muted)),
                          FilledButton(
                            key: const ValueKey('post-update'),
                            onPressed: _busy ? null : () => _post(ds),
                            child: _busy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: DColors.paper),
                                  )
                                : Text(ds.post),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_stage == 'resolved') ...[
                    const SizedBox(height: 8),
                    Text(ds.resolveNote, style: t.body(12, color: DColors.body)),
                  ],
                ],
              ),
            ),
          );

    return ListView(
      children: [
        head,
        composer,
        const SizedBox(height: 12),
        SizedBox(height: 560, child: TicketDetail(ticket: ticket, live: true, showActions: false)),
      ],
    );
  }
}

class _Evidence extends StatelessWidget {
  const _Evidence({required this.caption, required this.child, this.mono = false});
  final String caption;
  final Widget child;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final hindi = Localizations.maybeLocaleOf(context)?.languageCode == 'hi';
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 120, width: 180, color: DColors.track, child: child),
          const SizedBox(height: 4),
          Text(
            caption,
            style: mono ? DText.mono(11, color: DColors.muted) : DText(hindi).body(12, color: DColors.muted),
          ),
        ],
      ),
    );
  }
}
