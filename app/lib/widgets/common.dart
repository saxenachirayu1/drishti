import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers.dart';

Color statusColor(String status) => switch (status) {
      'active' || 'new' || 'still_present' || 'failed' => const Color(0xFFD32F2F),
      'complaint_sent' || 'sent' || 'approved' || 'running' || 'shrinking' => const Color(0xFFEF6C00),
      'cleanup_reported' || 'queued' || 'draft' => const Color(0xFF1565C0),
      'cleared' || 'closed' || 'matched' || 'done' => const Color(0xFF2E7D32),
      _ => const Color(0xFF757575),
    };

String fmtDate(DateTime? d) => d == null ? '-' : DateFormat('d MMM yyyy').format(d.toLocal());

String fmtDateTime(DateTime? d) => d == null ? '-' : DateFormat('d MMM yyyy, HH:mm').format(d.toLocal());

String fmtArea(double m2) => m2 >= 10000
    ? '${(m2 / 10000).toStringAsFixed(2)} ha'
    : '${NumberFormat.decimalPattern().format(m2.round())} m²';

class StatusChip extends ConsumerWidget {
  const StatusChip(this.status, {super.key, this.label});
  final String status;
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(label ?? s.status(status),
          style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Loading spinner, error with retry, or the data.
class AsyncView<T> extends ConsumerWidget {
  const AsyncView(this.value, {super.key, required this.builder, this.onRetry});
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return value.when(
      data: builder,
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(s.somethingWrong, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('$e', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: Text(s.retry)),
            ],
          ]),
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              ?trailing,
            ]),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 150,
              child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Expanded(child: Text(value)),
        ]),
      );
}

/// A labelled 0..1 bar, used for fire risk and the score parts.
class MeterBar extends StatelessWidget {
  const MeterBar({super.key, required this.label, required this.fraction, this.color, this.trailing});
  final String label;
  final double fraction;
  final Color? color;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label)),
            if (trailing != null) Text(trailing!, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.clamp(0, 1),
              minHeight: 8,
              color: color ?? Theme.of(context).colorScheme.primary,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ]),
      );
}

class EmptyNote extends ConsumerWidget {
  const EmptyNote({super.key, this.text});
  final String? text;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text ?? ref.watch(stringsProvider).nothingHere,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

void toast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

/// Runs an action, shows its error as a snackbar, and returns whether it worked.
Future<bool> guarded(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) toast(context, success);
    return true;
  } catch (e) {
    if (context.mounted) toast(context, '$e');
    return false;
  }
}

/// Street map or Esri satellite imagery, with the attribution each requires.
List<Widget> baseLayers({required bool satellite}) => [
      TileLayer(
        urlTemplate: satellite
            ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
            : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'org.drishti.app',
        maxNativeZoom: satellite ? 18 : 19,
      ),
    ];

Widget mapAttribution({required bool satellite}) => SimpleAttributionWidget(
      source: Text(satellite ? 'Esri, Maxar, Earthstar Geographics' : 'OpenStreetMap contributors'),
    );

/// A citizen report photo from the private bucket, through a signed URL.
class ReportPhoto extends ConsumerWidget {
  const ReportPhoto({super.key, required this.stored, this.size = 64});
  final String? stored;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (stored == null) return Icon(Icons.place_outlined, size: size / 2);
    final url = ref.watch(photoUrlProvider(stored!)).value;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: url == null
          ? SizedBox(width: size, height: size, child: const Icon(Icons.image_outlined))
          : Image.network(url, width: size, height: size, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => SizedBox(width: size, height: size, child: const Icon(Icons.broken_image))),
    );
  }
}
