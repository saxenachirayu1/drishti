import '../models/ticket.dart';

/// How far along the ring is filled for a stage (0 to 1). The ring is the
/// same mark everywhere: list rows, the tracking header, the officer queue.
double stageProgress(String stage) => switch (stage) {
  'received' || 'reopened' => 0.1,
  'assigned' => 0.3,
  'scheduled' => 0.45,
  'in_progress' => 0.65,
  'resolved' => 0.85,
  'proven_clean' => 1.0,
  _ => 0.0,
};

/// Stages a department may move a complaint to from [current]. Never
/// backwards; a resolved or proven complaint only takes notes.
List<String> nextStages(String current) {
  const order = ['received', 'reopened', 'assigned', 'scheduled', 'in_progress', 'resolved'];
  if (current == 'resolved' || current == 'proven_clean') return const [];
  final at = order.indexOf(current);
  return [
    for (final s in const ['assigned', 'scheduled', 'in_progress', 'resolved'])
      if (order.indexOf(s) >= at && s != current) s,
  ];
}

/// The reply clock, as a resident or an officer reads it.
sealed class ReplyClock {
  const ReplyClock();
}

/// Answered: how long the first reply took and whether it was in time.
class Replied extends ReplyClock {
  const Replied(this.took, {required this.onTime});
  final Duration took;
  final bool onTime;
}

/// Waiting, with time left.
class DueIn extends ReplyClock {
  const DueIn(this.left);
  final Duration left;
}

/// Waiting past the target.
class Overdue extends ReplyClock {
  const Overdue(this.by);
  final Duration by;
}

/// No target known.
class NoClock extends ReplyClock {
  const NoClock();
}

ReplyClock replyClock(Ticket t, DateTime now) {
  final due = t.replyDueAt;
  final created = t.createdAt;
  if (t.firstReplyAt != null && created != null) {
    return Replied(t.firstReplyAt!.difference(created), onTime: due == null || !t.firstReplyAt!.isAfter(due));
  }
  if (due == null) return const NoClock();
  final left = due.difference(now);
  return left.isNegative ? Overdue(-left) : DueIn(left);
}

/// Hours and minutes, short: "45 min", "3 h", "2 d 4 h".
String shortDuration(Duration d, {bool hindi = false}) {
  final mins = d.inMinutes.abs();
  final h = hindi ? 'घं' : 'h';
  final m = hindi ? 'मि' : 'min';
  final dd = hindi ? 'दिन' : 'd';
  if (mins < 60) return '${mins < 1 ? 1 : mins} $m';
  final hours = mins ~/ 60;
  if (hours < 48) return '$hours $h';
  final days = hours ~/ 24;
  final rest = hours % 24;
  return rest == 0 ? '$days $dd' : '$days $dd $rest $h';
}

/// Queue order for a department: overdue first (oldest deadline first), then
/// burning, then by deadline; closed complaints last.
List<Ticket> queueOrder(List<Ticket> list, DateTime now) {
  int rank(Ticket t) {
    if (t.isClosed) return 3;
    final c = replyClock(t, now);
    if (c is Overdue) return 0;
    if (t.category == 'burning' && t.firstReplyAt == null) return 1;
    return 2;
  }

  final out = [...list];
  out.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    final da = a.replyDueAt ?? a.createdAt ?? now;
    final db = b.replyDueAt ?? b.createdAt ?? now;
    return da.compareTo(db);
  });
  return out;
}

/// What a resident typed into "track": tolerant of spaces, case and a
/// missing prefix ("q 412" or "0412" → "DRI-Q-0412"). Null if it cannot be one.
String? normaliseTicket(String raw) {
  final s = raw.toUpperCase().replaceAll(RegExp(r'[\s_]'), '');
  final m = RegExp(r'^(?:DRI-?Q-?|Q-?)?(\d{1,6})$').firstMatch(s);
  if (m == null) return null;
  final n = m.group(1)!;
  return 'DRI-Q-${n.length < 4 ? n.padLeft(4, '0') : n}';
}
