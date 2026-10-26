import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../complaints_providers.dart';
import '../models/ticket.dart';
import '../services/tracking_logic.dart';
import '../theme/d_strings.dart';
import '../theme/drishti_theme.dart';
import '../widgets/common.dart';
import '../widgets/d_widgets.dart';

/// Track a complaint: by code (anyone), or your own list (signed in), with
/// the department's updates arriving live.
class TrackScreen extends ConsumerStatefulWidget {
  const TrackScreen({super.key, this.standalone = false, this.reportId, this.code});
  final bool standalone;

  /// Open straight on one of the viewer's complaints.
  final String? reportId;

  /// Open straight on a public lookup.
  final String? code;

  @override
  ConsumerState<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends ConsumerState<TrackScreen> {
  final _code = TextEditingController();
  String? _codeError;

  /// What is open on the right (or pushed on phones).
  ({String? id, String? code})? _open;

  @override
  void initState() {
    super.initState();
    if (widget.reportId != null || widget.code != null) _open = (id: widget.reportId, code: widget.code);
    if (widget.code != null) _code.text = widget.code!;
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _lookup() {
    final ds = ref.read(dsProvider);
    final code = normaliseTicket(_code.text);
    if (code == null) {
      setState(() => _codeError = ds.ticketBad);
      return;
    }
    _code.text = code;
    // Your own complaint opens with live updates and photos.
    final mine = ref.read(myTicketsProvider).value ?? const <Ticket>[];
    String? ownId;
    for (final t in mine) {
      if (t.ticket == code) ownId = t.id;
    }
    _show(ownId != null ? (id: ownId, code: null) : (id: null, code: code));
  }

  void _show(({String? id, String? code}) which) {
    setState(() {
      _codeError = null;
      _open = which;
    });
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (!wide) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Consumer(
            builder: (context, ref, _) {
              final ds = ref.watch(dsProvider);
              return Scaffold(
                appBar: AppBar(title: Text(ds.trackTitle)),
                body: TicketView(reportId: which.id, code: which.code),
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
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final signedIn = ref.watch(meProvider) != null;
    final open = _open;

    final list = ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(ds.trackTitle, style: t.head(28)),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('ticket-code'),
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _lookup(),
                style: DText.mono(16),
                decoration: InputDecoration(
                  labelText: ds.ticketLabel,
                  hintText: ds.ticketHint,
                  errorText: _codeError,
                  errorMaxLines: 2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 56,
              child: FilledButton(onPressed: _lookup, child: Text(ds.searchBtn)),
            ),
          ],
        ),
        const SizedBox(height: 28),
        if (signedIn) ...[
          DLabel(ds.yourComplaints, hindi: ds.hindi),
          const SizedBox(height: 8),
          AsyncView(
            ref.watch(myTicketsProvider),
            onRetry: () => ref.invalidate(myTicketsProvider),
            builder: (List<Ticket> mine) => mine.isEmpty
                ? Text(ds.noComplaints, style: t.body(14, color: DColors.muted))
                : Column(
                    children: [
                      for (final x in mine)
                        TicketRow(
                          ticket: x,
                          selected: wide && open?.id == x.id,
                          onTap: () => _show((id: x.id, code: null)),
                        ),
                    ],
                  ),
          ),
        ],
      ],
    );

    Widget body;
    if (wide) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 400, child: list),
          const VerticalDivider(width: 1),
          Expanded(
            child: open == null
                ? Center(
                    child: Text(ds.pickOne, style: t.body(15, color: DColors.muted)),
                  )
                : TicketView(key: ValueKey(open), reportId: open.id, code: open.code),
          ),
        ],
      );
    } else {
      body = list;
    }

    if (!widget.standalone) return body;
    return Scaffold(
      appBar: AppBar(title: Text(ds.trackTitle)),
      body: body,
    );
  }
}

/// One line in a list of complaints: ring, what and where, the reply clock.
class TicketRow extends ConsumerWidget {
  const TicketRow({super.key, required this.ticket, required this.onTap, this.selected = false});
  final Ticket ticket;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ds = ref.watch(dsProvider);
    final t = DText(ds.hindi);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final clock = replyClock(ticket, now);
    final overdue = clock is Overdue;
    final where = [
      if (ticket.locality != null) ticket.locality!,
      if (ticket.wardNo != null) ds.ward(ticket.wardNo, null),
    ].join(' · ');
    return Material(
      color: selected ? DColors.selected : DColors.surface,
      child: InkWell(
        key: ValueKey('ticket-${ticket.id}'),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: const BorderSide(color: DColors.ruleSoft),
              left: BorderSide(color: overdue ? DColors.fire : (selected ? DColors.ink : DColors.rule), width: 4),
            ),
          ),
          child: Row(
            children: [
              StageRing(progress: stageProgress(ticket.stage), color: stageColor(ticket.stage), size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(ticket.ticket ?? '', style: DText.mono(12, color: DColors.evidence)),
                        const Spacer(),
                        StageStamp(ticket.stage, ds: ds, small: true),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${ds.typeName(ticket.category)}${where.isEmpty ? '' : ' · $where'}',
                      style: t.body(14, weight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      ds.clockText(clock, complaintType(ticket.category).replyHours),
                      style: t.body(
                        12,
                        color: overdue ? DColors.fire : DColors.muted,
                        weight: overdue ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A complaint's header and timeline. With [reportId] it is the reporter's
/// (or staff) view with live updates; with [code] the public view.
class TicketView extends ConsumerWidget {
  const TicketView({super.key, this.reportId, this.code, this.showActions = true});
  final String? reportId;
  final String? code;
  final bool showActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ds = ref.watch(dsProvider);
    final t = DText(ds.hindi);
    final live = reportId != null;
    final value = live ? ref.watch(ticketProvider(reportId!)) : ref.watch(trackProvider(code!));
    return AsyncView(
      value,
      onRetry: () => live ? ref.invalidate(ticketProvider(reportId!)) : ref.invalidate(trackProvider(code!)),
      builder: (Ticket? ticket) {
        if (ticket == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(ds.ticketMissing, style: t.body(16, color: DColors.muted)),
            ),
          );
        }
        return TicketDetail(ticket: ticket, live: live, showActions: showActions);
      },
    );
  }
}

class TicketDetail extends ConsumerWidget {
  const TicketDetail({super.key, required this.ticket, required this.live, this.showActions = true});
  final Ticket ticket;
  final bool live;
  final bool showActions;

  Future<void> _reopen(BuildContext context, WidgetRef ref, DS ds) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ds.reopenTitle, style: DText(ds.hindi).head(22)),
        content: TextField(
          controller: reason,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(hintText: ds.reopenHint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ds.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ds.reopenSend)),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (ok != true || !context.mounted) return;
    final done = await guarded(
      context,
      () => ref.read(complaintsApiProvider).reopen(ticket.id, reason: text),
      success: ds.reopened,
    );
    if (done) ref.invalidate(ticketProvider(ticket.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ds = ref.watch(dsProvider);
    final t = DText(ds.hindi);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final me = ref.watch(meProvider);
    final mine = me != null && ticket.userId == me;
    final clock = replyClock(ticket, now);
    final hours = complaintType(ticket.category).replyHours;
    final where = ticket.locality ?? '';

    final header = Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DColors.ink, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SelectableText(
                ticket.ticket ?? '',
                style: DText.mono(14, color: DColors.evidence, weight: FontWeight.w500),
              ),
              IconButton(
                tooltip: ds.copyCode,
                iconSize: 18,
                icon: const Icon(Icons.copy_outlined),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: ticket.ticket ?? ''));
                  toast(context, ds.copied);
                },
              ),
              const Spacer(),
              if (live)
                Tooltip(
                  message: ds.liveHint,
                  child: Text(
                    '● ${ds.live}',
                    style: t.body(12, weight: FontWeight.w700, color: DColors.clean),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              StageRing(
                progress: stageProgress(ticket.stage),
                color: stageColor(ticket.stage),
                size: 52,
                label: ds.headline(ticket.stage),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(header: true, child: Text(ds.headline(ticket.stage), style: t.head(24))),
                    Text(
                      '${ds.typeName(ticket.category)}${where.isEmpty ? '' : ' · $where'}',
                      style: t.body(14, color: DColors.body),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Chip(
                '${ds.ward(ticket.wardNo, ticket.wardName)} · ${ds.deptName(ticket.department)}',
                color: DColors.ink,
              ),
              if (clock is! NoClock)
                _Chip(
                  ds.clockText(clock, hours),
                  color: switch (clock) {
                    Replied(:final onTime) => onTime ? DColors.clean : DColors.filedText,
                    Overdue() => DColors.fire,
                    _ => DColors.body,
                  },
                  strong: clock is! DueIn,
                ),
            ],
          ),
        ],
      ),
    );

    final updates = ticket.updates.reversed.toList();
    final timeline = Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        children: [
          if (ticket.stage != 'proven_clean')
            _TimelineEntry(
              dotColor: DColors.clean,
              dashed: true,
              faded: true,
              label: ds.nextProof,
              labelColor: DColors.clean,
              body: ds.nextProofBody,
              last: updates.isEmpty,
            ),
          for (var i = 0; i < updates.length; i++)
            _TimelineEntry(
              dotColor: stageColor(updates[i].stage),
              label: ds.stamp(updates[i].stage),
              labelColor: updates[i].stage == 'in_progress' ? DColors.filedText : stageColor(updates[i].stage),
              time: updates[i].createdAt,
              body: updates[i].message,
              author: switch (updates[i].authorRole) {
                'department' => ds.byDept,
                'citizen' => mine ? ds.byYou : null,
                _ => ds.bySystem,
              },
              photo: updates[i].photoPath,
              hasPhoto: updates[i].hasPhoto,
              hindi: ds.hindi,
              last: i == updates.length - 1,
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: ListView(children: [header, timeline])),
        if (showActions && mine && ticket.isClosed)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: DColors.rule)),
            ),
            child: DSecondaryButton(
              key: const ValueKey('reopen'),
              label: ds.reopen,
              expand: true,
              height: 48,
              onPressed: () => _reopen(context, ref, ds),
            ),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.color, this.strong = false});
  final String text;
  final Color color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final hindi = Localizations.maybeLocaleOf(context)?.languageCode == 'hi';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: DColors.surface,
        border: Border.all(color: strong ? color : DColors.rule),
      ),
      child: Text(
        text,
        style: DText(hindi).body(12, color: color, weight: strong ? FontWeight.w600 : FontWeight.w400, height: 1.3),
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    required this.dotColor,
    required this.label,
    required this.labelColor,
    this.body,
    this.time,
    this.author,
    this.photo,
    this.hasPhoto = false,
    this.dashed = false,
    this.faded = false,
    this.hindi = false,
    this.last = false,
  });

  final Color dotColor;
  final String label;
  final Color labelColor;
  final String? body;
  final DateTime? time;
  final String? author;
  final String? photo;
  final bool hasPhoto;
  final bool dashed;
  final bool faded;
  final bool hindi;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = DText(hindi);
    final when = time == null ? '' : DateFormat('d MMM, h:mm a').format(time!.toLocal()).toUpperCase();
    return Opacity(
      opacity: faded ? 0.6 : 1,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 22,
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dashed ? Colors.transparent : dotColor,
                      border: dashed ? Border.all(color: dotColor, width: 2) : null,
                    ),
                  ),
                  if (!last)
                    const Expanded(
                      child: SizedBox(width: 2, child: ColoredBox(color: DColors.rule)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: t.body(11, weight: FontWeight.w700, color: labelColor).copyWith(letterSpacing: 0.6),
                          ),
                        ),
                        if (when.isNotEmpty) Text(when, style: DText.mono(11, color: DColors.muted)),
                      ],
                    ),
                    if (body != null && body!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(body!, style: t.body(14)),
                    ],
                    if (photo != null) ...[
                      const SizedBox(height: 6),
                      _UpdatePhoto(stored: photo!),
                    ] else if (hasPhoto) ...[
                      const SizedBox(height: 4),
                      Text(
                        '▣ ${hindi ? 'जगह की फ़ोटो जुड़ी है' : 'A site photo is attached'}',
                        style: t.body(12, color: DColors.muted),
                      ),
                    ],
                    if (author != null) ...[
                      const SizedBox(height: 2),
                      Text(author!, style: t.body(12, color: DColors.muted)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdatePhoto extends ConsumerWidget {
  const _UpdatePhoto({required this.stored});
  final String stored;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(ticketPhotoProvider(stored)).value;
    final ds = ref.watch(dsProvider);
    return Semantics(
      image: true,
      label: ds.photoAttached,
      child: SizedBox(
        width: 160,
        height: 110,
        child: url == null
            ? const ColoredBox(color: DColors.track)
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(color: DColors.track),
              ),
      ),
    );
  }
}
