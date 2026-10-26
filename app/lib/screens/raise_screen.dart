import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../complaints_providers.dart';
import '../models/ticket.dart';
import '../theme/d_strings.dart';
import '../theme/drishti_theme.dart';
import '../widgets/auth_form.dart';
import '../widgets/common.dart';
import '../widgets/d_widgets.dart';
import 'navigation.dart';

/// False in widget tests: no map tiles from the network and no GPS prompt.
final liveDeviceProvider = Provider<bool>((ref) => true);

/// Raise a complaint: what, where, a photo. The panel at the bottom says who
/// it will go to before it is sent, so nobody files into a void.
class RaiseScreen extends ConsumerStatefulWidget {
  const RaiseScreen({super.key, this.standalone = false});

  /// Pushed on its own (from the home page) rather than shown as a tab.
  final bool standalone;

  @override
  ConsumerState<RaiseScreen> createState() => _RaiseScreenState();
}

class _RaiseScreenState extends ConsumerState<RaiseScreen> {
  final _note = TextEditingController();
  final _map = MapController();
  String _type = 'dump';
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
    final ds = ref.read(dsProvider);
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw StateError('denied');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      final p = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _pin = p);
      _map.move(p, 16);
    } catch (_) {
      if (mounted) toast(context, ds.noLocation);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (mounted) setState(() => _photo = bytes);
  }

  void _photoMenu(DS ds) => showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(ds.camera),
            onTap: () {
              Navigator.pop(ctx);
              _pick(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(ds.gallery),
            onTap: () {
              Navigator.pop(ctx);
              _pick(ImageSource.gallery);
            },
          ),
        ],
      ),
    ),
  );

  Future<void> _submit() async {
    final ds = ref.read(dsProvider);
    final pin = _pin;
    if (pin == null) {
      toast(context, ds.pickPlaceFirst);
      return;
    }
    setState(() => _busy = true);
    try {
      final note = _note.text.trim();
      final res = await ref
          .read(complaintsApiProvider)
          .submit(
            lat: pin.latitude,
            lng: pin.longitude,
            category: _type,
            note: note.isEmpty ? null : note,
            photo: _photo,
          );
      ref.invalidate(myTicketsProvider);
      if (!mounted) return;
      setState(() {
        _photo = null;
        _note.clear();
      });
      await _sent(ds, res);
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sent(DS ds, Map<String, dynamic> res) {
    final t = DText(ds.hindi);
    final code = res['ticket'] as String? ?? '';
    final site = res['site_id'] as String?;
    final id = res['id'] as String?;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const StageRing(progress: 0.1, color: DColors.ink, size: 36),
            const SizedBox(width: 12),
            Expanded(child: Text(ds.sentTitle, style: t.head(24))),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                code,
                style: DText.mono(22, color: DColors.evidence, weight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Text(ds.sentBody(code, ds.deptName(res['department'] as String?)), style: t.body(15)),
              if (site != null) ...[
                const SizedBox(height: 8),
                Text(ds.sentMatched(site), style: t.body(14, color: DColors.body)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              toast(ctx, ds.copied);
            },
            child: Text(ds.copyCode),
          ),
          if (id != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                openTrack(context, reportId: id);
              },
              child: Text(ds.followIt),
            ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(ds.done)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = ref.watch(dsProvider);
    final t = DText(ds.hindi);
    final signedIn = ref.watch(meProvider) != null;
    final live = ref.watch(liveDeviceProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    Widget body;
    if (!signedIn) {
      body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(ds.raiseTitle, style: t.head(28)),
              const SizedBox(height: 8),
              Text(ds.signInToRaise, style: t.body(15, color: DColors.body)),
              const SizedBox(height: 16),
              const AuthForm(),
            ],
          ),
        ),
      );
    } else {
      if (!_askedGps && live) {
        _askedGps = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _locate();
        });
      }
      final form = [
        _types(ds, t),
        const SizedBox(height: 20),
        _where(ds, t, live, wide),
        const SizedBox(height: 20),
        _photoAndNote(ds, t),
        const SizedBox(height: 20),
        _goesTo(ds, t),
      ];
      body = Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: form),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: const BoxDecoration(
              color: DColors.paper,
              border: Border(top: BorderSide(color: DColors.rule)),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: DPrimaryButton(
                  key: const ValueKey('raise-submit'),
                  label: _busy ? ds.sending : ds.send,
                  busy: _busy,
                  expand: true,
                  onPressed: _submit,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (!widget.standalone) return body;
    return Scaffold(
      appBar: AppBar(title: Text(ds.raiseTitle)),
      body: SafeArea(top: false, child: body),
    );
  }

  Widget _types(DS ds, DText t) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DLabel(ds.step1, hindi: ds.hindi),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, box) {
          final cols = box.maxWidth >= 640 ? 4 : 2;
          final w = (box.maxWidth - 8 * (cols - 1)) / cols;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in complaintTypes)
                SizedBox(
                  width: w,
                  child: _TypeTile(
                    key: ValueKey('type-${c.id}'),
                    label: ds.typeName(c.id),
                    hint: ds.typeHint(c.id),
                    selected: _type == c.id,
                    urgent: c.id == 'burning',
                    hindi: ds.hindi,
                    onTap: () => setState(() => _type = c.id),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );

  Widget _where(DS ds, DText t, bool live, bool wide) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DLabel(ds.step2, hindi: ds.hindi),
      const SizedBox(height: 4),
      Text(ds.tapMap, style: t.body(13, color: DColors.muted)),
      const SizedBox(height: 8),
      SizedBox(
        height: wide ? 320 : 240,
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: DColors.rule)),
          child: FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: const LatLng(18.52, 73.855),
              initialZoom: 12,
              onTap: (_, p) => setState(() => _pin = p),
            ),
            children: [
              if (live) ...baseLayers(satellite: false),
              if (_pin != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _pin!,
                      width: 28,
                      height: 34,
                      alignment: Alignment.topCenter,
                      child: const CustomPaint(painter: _PinPainter()),
                    ),
                  ],
                ),
              if (live) mapAttribution(satellite: false),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            icon: _locating
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location, size: 18),
            label: Text(_locating ? ds.locating : ds.useLocation),
            onPressed: _locating ? null : _locate,
          ),
          if (_pin != null)
            Text(
              '${_pin!.latitude.toStringAsFixed(5)}°N ${_pin!.longitude.toStringAsFixed(5)}°E',
              style: DText.mono(12, color: DColors.muted),
            ),
        ],
      ),
    ],
  );

  Widget _photoAndNote(DS ds, DText t) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DLabel(ds.step3, hindi: ds.hindi),
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            height: 104,
            child: _photo == null
                ? OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: const BorderSide(color: DColors.ink, width: 1.5, style: BorderStyle.solid),
                    ),
                    onPressed: () => _photoMenu(ds),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.photo_camera_outlined),
                        const SizedBox(height: 4),
                        Text(
                          ds.addPhoto,
                          textAlign: TextAlign.center,
                          style: t.body(13, weight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(_photo!, fit: BoxFit.cover),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: IconButton.filled(
                          tooltip: ds.removePhoto,
                          style: IconButton.styleFrom(backgroundColor: DColors.ink),
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => setState(() => _photo = null),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              key: const ValueKey('raise-note'),
              controller: _note,
              maxLines: 4,
              minLines: 4,
              maxLength: 500,
              decoration: InputDecoration(labelText: ds.noteLabel, hintText: ds.noteHint, alignLabelWithHint: true),
            ),
          ),
        ],
      ),
      Text(ds.photoPrivate, style: t.body(12, color: DColors.muted)),
    ],
  );

  Widget _goesTo(DS ds, DText t) {
    final pin = _pin;
    final type = complaintType(_type);
    RoutePreview? preview;
    if (pin != null) {
      double r5(double v) => (v * 1e5).roundToDouble() / 1e5;
      preview = ref.watch(routePreviewProvider((r5(pin.latitude), r5(pin.longitude), _type))).value;
    }
    final dept = preview?.department ?? type.defaultDepartment;
    final hours = preview?.replyHours ?? type.replyHours;
    return DPanel(
      key: const ValueKey('goes-to'),
      leftRule: DColors.ink,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ds.goesTo,
            style: t.body(12, weight: FontWeight.w700, color: DColors.muted),
          ),
          const SizedBox(height: 2),
          Text(
            preview == null ? ds.deptName(dept) : '${ds.ward(preview.wardNo, preview.wardName)} · ${ds.deptName(dept)}',
            style: t.body(16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            ds.deptWhy(_type, onPwdRoad: preview?.onPwdRoad ?? false),
            style: t.body(13, color: DColors.body),
          ),
          const SizedBox(height: 4),
          Text(ds.replyTarget(hours), style: DText.mono(12)),
        ],
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    super.key,
    required this.label,
    required this.hint,
    required this.selected,
    required this.urgent,
    required this.hindi,
    required this.onTap,
  });
  final String label;
  final String hint;
  final bool selected;
  final bool urgent;
  final bool hindi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DText(hindi);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: DColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: BorderSide(color: selected ? DColors.ink : const Color(0xFFC9CDD6), width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: selected ? DColors.signal : Colors.transparent, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(label, style: t.body(15, weight: FontWeight.w600, height: 1.25)),
                    ),
                    if (urgent) ...[const SizedBox(width: 6), Text('▲', style: t.body(11, color: DColors.fire))],
                  ],
                ),
                Text(hint, style: t.body(12, color: DColors.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The map pin: the mark's square pupil on an ink drop.
class _PinPainter extends CustomPainter {
  const _PinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final drop = Path()
      ..moveTo(w / 2, h)
      ..cubicTo(w * 0.1, h * 0.62, 0, h * 0.45, 0, w / 2)
      ..arcToPoint(Offset(w, w / 2), radius: Radius.circular(w / 2))
      ..cubicTo(w, h * 0.45, w * 0.9, h * 0.62, w / 2, h)
      ..close();
    canvas.drawPath(drop, Paint()..color = DColors.ink);
    final s = w * 0.3;
    canvas.drawRect(
      Rect.fromCenter(center: Offset(w / 2, w / 2), width: s, height: s),
      Paint()..color = DColors.signal,
    );
  }

  @override
  bool shouldRepaint(_PinPainter old) => false;
}
