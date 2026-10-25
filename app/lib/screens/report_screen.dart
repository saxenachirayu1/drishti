import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../models/place.dart';
import '../providers.dart';
import '../widgets/auth_form.dart';
import '../widgets/common.dart';
import 'site_detail_screen.dart';

/// Citizen layer: drop a pin, add a note and photo, and see your reports.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  final _note = TextEditingController();
  final _map = MapController();
  LatLng? _pin;
  Uint8List? _photo;
  String _photoExt = 'jpg';
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 80);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final name = file.name.toLowerCase();
    setState(() {
      _photo = bytes;
      _photoExt = name.endsWith('.png') ? 'png' : (name.endsWith('.webp') ? 'webp' : 'jpg');
    });
  }

  Future<void> _submit() async {
    final s = ref.read(stringsProvider);
    final repo = ref.read(repoProvider);
    final pin = _pin;
    if (pin == null) {
      toast(context, s.tapToPlace);
      return;
    }
    setState(() => _busy = true);
    try {
      final photoUrl = _photo == null ? null : await repo.uploadReportPhoto(_photo!, ext: _photoExt);
      final res = await repo.submitReport(
        lat: pin.latitude,
        lng: pin.longitude,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        photoUrl: photoUrl,
      );
      ref.invalidate(myReportsProvider);
      ref.invalidate(allReportsProvider);
      if (!mounted) return;
      final matched = res['status'] == 'matched';
      setState(() {
        _pin = null;
        _photo = null;
        _note.clear();
      });
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(matched ? '${s.reportMatched} (${res['site_id']}, ${res['distance_m']} m).' : s.reportFlagged),
          actions: [
            if (matched)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => SiteDetailScreen(siteId: res['site_id'] as String)));
                },
                child: Text(s.open),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final signedIn = ref.watch(userIdProvider) != null;
    final cities = ref.watch(citiesProvider).value ?? const <City>[];

    if (!signedIn) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24), children: [
            Text(s.reportTitle, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(s.signInToReport),
            const SizedBox(height: 16),
            const AuthForm(),
          ]),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Text(s.reportTitle, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(s.reportHint),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final c in cities)
              if (c.center != null)
                ActionChip(label: Text(c.name), onPressed: () => _map.move(c.center!, 13)),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: const LatLng(22.7, 75.85),
                  initialZoom: 11,
                  onTap: (_, p) => setState(() => _pin = p),
                ),
                children: [
                  ...baseLayers(satellite: false),
                  if (_pin != null)
                    MarkerLayer(markers: [
                      Marker(
                        point: _pin!,
                        width: 40,
                        height: 40,
                        alignment: Alignment.topCenter,
                        child: const Icon(Icons.location_on, color: Colors.purple, size: 40),
                      ),
                    ]),
                  mapAttribution(satellite: false),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              _pin == null
                  ? s.tapToPlace
                  : '${s.location}: ${_pin!.latitude.toStringAsFixed(5)}, ${_pin!.longitude.toStringAsFixed(5)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: InputDecoration(labelText: s.note, hintText: s.notePlaceholder, border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton.icon(
                icon: const Icon(Icons.photo_camera), label: Text(s.camera), onPressed: () => _pick(ImageSource.camera)),
            const SizedBox(width: 8),
            OutlinedButton.icon(
                icon: const Icon(Icons.photo_library), label: Text(s.gallery), onPressed: () => _pick(ImageSource.gallery)),
            const SizedBox(width: 12),
            if (_photo != null)
              Stack(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(_photo!, width: 64, height: 64, fit: BoxFit.cover)),
                Positioned(
                  right: -8,
                  top: -8,
                  child: IconButton(
                      icon: const Icon(Icons.cancel, size: 18), onPressed: () => setState(() => _photo = null)),
                ),
              ]),
          ]),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: Text(s.submit),
            onPressed: _busy ? null : _submit,
          ),
          const SizedBox(height: 24),
          Text(s.myReports, style: Theme.of(context).textTheme.titleMedium),
          AsyncView(ref.watch(myReportsProvider), onRetry: () => ref.invalidate(myReportsProvider), builder: (list) {
            if (list.isEmpty) return const EmptyNote();
            return Column(children: [
              for (final r in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: r.photoUrl == null
                      ? const Icon(Icons.place_outlined)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(r.photoUrl!, width: 48, height: 48, fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(Icons.broken_image)),
                        ),
                  title: Text(r.note ?? '-'),
                  subtitle: Text('${fmtDateTime(r.createdAt)}'
                      '${r.linkedSiteId != null ? ' · ${s.site} ${r.linkedSiteId}' : ''}'),
                  trailing: StatusChip(r.status),
                  onTap: r.linkedSiteId == null
                      ? null
                      : () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => SiteDetailScreen(siteId: r.linkedSiteId!))),
                ),
            ]);
          }),
        ]),
      ),
    );
  }
}
