import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../models/place.dart';
import '../providers.dart';
import '../widgets/auth_form.dart';
import '../widgets/common.dart';
import 'site_detail_screen.dart';

/// Citizen layer (A-19): the pin starts at the phone's GPS position (tap the
/// map to move it), add a note and a photo, and see your reports.
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
  bool _busy = false;
  bool _locating = false;
  bool _askedGps = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw StateError('denied');
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
      final p = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _pin = p);
      _map.move(p, 16);
    } catch (_) {
      if (mounted) toast(context, ref.read(stringsProvider).locationOff);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _photo = bytes);
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
      final photo = _photo == null ? null : await repo.uploadReportPhoto(_photo!);
      final res = await repo.submitReport(
        lat: pin.latitude,
        lng: pin.longitude,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        photoUrl: photo,
      );
      ref.invalidate(myReportsProvider);
      ref.invalidate(allReportsProvider);
      if (!mounted) return;
      final matched = res['status'] == 'matched';
      setState(() {
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.ok)),
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

    // Auto GPS the first time the signed-in reporter opens the screen.
    if (!_askedGps) {
      _askedGps = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Text(s.reportTitle, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(s.reportHint),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ActionChip(
              avatar: _locating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location, size: 18),
              label: Text(s.useMyLocation),
              onPressed: _locating ? null : _locate,
            ),
            for (final c in cities)
              if (c.center != null) ActionChip(label: Text(c.name), onPressed: () => _map.move(c.center!, 13)),
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
                        child: Icon(Icons.location_on, color: Colors.purple, size: 40, semanticLabel: s.location),
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
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(
                icon: const Icon(Icons.photo_camera), label: Text(s.camera), onPressed: () => _pick(ImageSource.camera)),
            OutlinedButton.icon(
                icon: const Icon(Icons.photo_library), label: Text(s.gallery), onPressed: () => _pick(ImageSource.gallery)),
            if (_photo != null)
              InputChip(
                avatar: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(_photo!, width: 32, height: 32, fit: BoxFit.cover)),
                label: Text(s.addPhoto),
                onDeleted: () => setState(() => _photo = null),
              ),
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
                  leading: ReportPhoto(stored: r.photoUrl, size: 48),
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
