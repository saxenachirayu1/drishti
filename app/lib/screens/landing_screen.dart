import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../complaints_providers.dart';
import '../models/ticket.dart';
import '../services/area_search.dart';
import '../providers.dart';
import '../theme/d_strings.dart';
import '../theme/drishti_theme.dart';
import '../widgets/auth_form.dart';
import '../widgets/d_widgets.dart';
import 'navigation.dart';

/// The front door: one promise, one search, two actions, and a reason to
/// come back. Light on numbers on purpose; the impact page has those.
class LandingScreen extends ConsumerStatefulWidget {
  const LandingScreen({super.key});

  @override
  ConsumerState<LandingScreen> createState() => _LandingScreenState();
}

sealed class _Search {
  const _Search();
}

class _Empty extends _Search {
  const _Empty();
}

class _Miss extends _Search {
  const _Miss();
}

class _BadPin extends _Search {
  const _BadPin();
}

class _Failed extends _Search {
  const _Failed();
}

class _Hit extends _Search {
  const _Hit(this.area);
  final AreaHit area;
}

class _LandingScreenState extends ConsumerState<LandingScreen> {
  final _query = TextEditingController();
  final _queryFocus = FocusNode();
  final _scroll = ScrollController();
  final _searchKey = GlobalKey();
  _Search? _result;
  bool _searching = false;
  int _stop = 0;
  bool _followBusy = false;

  @override
  void dispose() {
    _query.dispose();
    _queryFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    final parsed = parseAreaQuery(q);
    if (parsed is TooShort) {
      setState(() => _result = const _Empty());
      return;
    }
    if (parsed is BadPin) {
      setState(() => _result = const _BadPin());
      return;
    }
    setState(() => _searching = true);
    _Search r;
    try {
      final hits = await ref.read(complaintsApiProvider).areaLookup(q);
      r = hits.isEmpty ? const _Miss() : _Hit(hits.first);
    } catch (_) {
      r = const _Failed();
    }
    if (!mounted) return;
    setState(() {
      _result = r;
      _searching = false;
    });
  }

  void _findArea() {
    final ctx = _searchKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), alignment: 0.2);
    }
    _queryFocus.requestFocus();
  }

  Future<void> _toggleFollow(AreaHit area, bool on) async {
    final ds = ref.read(dsProvider);
    if (ref.read(meProvider) == null) {
      await showSignInSheet(context, ds.followSignIn);
      if (ref.read(meProvider) == null) return;
    }
    setState(() => _followBusy = true);
    try {
      await ref.read(complaintsApiProvider).setFollow(area.id, on);
      ref.invalidate(followsProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  void _about(String title, String body) {
    final ds = ref.read(dsProvider);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: DText(ds.hindi).head(24)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(body, style: DText(ds.hindi).body(15)),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ds.close))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = ref.watch(dsProvider);
    final t = DText(ds.hindi);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 960;
    final gutter = width < 600 ? 20.0 : 32.0;

    return Scaffold(
      backgroundColor: DColors.paper,
      body: SingleChildScrollView(
        controller: _scroll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _hero(context, ds, t, wide, gutter),
            _journey(ds, t, wide, gutter),
            _goal(ds, t, gutter),
            _follow(ds, t, gutter),
            _closing(ds, t, gutter),
          ],
        ),
      ),
    );
  }

  // --- hero -------------------------------------------------------------------

  Widget _hero(BuildContext context, DS ds, DText t, bool wide, double gutter) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(ds.h1, style: t.head(narrow ? 40 : (wide ? 64 : 52), color: DColors.paper, height: 1.04)),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(ds.sub, style: t.body(narrow ? 17 : 19, color: DColors.onInkMuted)),
        ),
        const SizedBox(height: 28),
        _searchBox(ds, t),
        const SizedBox(height: 22),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            DPrimaryButton(label: ds.raise, onPressed: () => openRaise(context)),
            DSecondaryButton(label: ds.openMap, onInk: true, onPressed: () => openShell(context, 'map')),
          ],
        ),
      ],
    );
    final picture = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BeforeAfter(ds: ds),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(ds.caption, style: t.body(13, color: DColors.onInkFaint)),
            Text('18.52°N 73.85°E · 10 M/PX', style: DText.mono(12, color: DColors.onInkFaint)),
          ],
        ),
      ],
    );

    return ColoredBox(
      color: DColors.ink,
      child: DPage(
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 72),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _nav(ds),
            SizedBox(height: wide ? 56 : 32),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 11, child: copy),
                  const SizedBox(width: 56),
                  Expanded(flex: 12, child: picture),
                ],
              )
            else ...[
              copy,
              const SizedBox(height: 40),
              picture,
            ],
          ],
        ),
      ),
    );
  }

  Widget _nav(DS ds) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children: [
        const DrishtiWordmark(onInk: true),
        Wrap(
          spacing: 24,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DNavLink(label: ds.navMap, onPressed: () => openShell(context, 'map')),
            DNavLink(label: ds.navTrack, onPressed: () => openTrack(context)),
            DNavLink(label: ds.navImpact, onPressed: () => openImpact(context)),
            DNavLink(label: ds.navOfficials, onPressed: () => openShell(context, 'console')),
            LanguageSwitch(
              hindi: ds.hindi,
              onChanged: (hi) {
                ref.read(localeProvider.notifier).set(hi ? 'hi' : 'en');
                setState(() => _result = null);
              },
            ),
          ],
        ),
      ],
    ),
  );

  Widget _searchBox(DS ds, DText t) {
    final r = _result;
    return ConstrainedBox(
      key: _searchKey,
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ds.searchLabel,
            style: t.body(14, weight: FontWeight.w600, color: DColors.paper),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('area-search'),
                  controller: _query,
                  focusNode: _queryFocus,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  style: t.body(16, color: DColors.paper),
                  cursorColor: DColors.signal,
                  decoration: InputDecoration(
                    hintText: ds.searchHint,
                    hintStyle: t.body(16, color: DColors.onInkFaint),
                    filled: true,
                    fillColor: DColors.inkRaised,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
                    enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                      borderSide: BorderSide(color: DColors.inkLine, width: 1.5),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                      borderSide: BorderSide(color: DColors.signal, width: 2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DPrimaryButton(label: ds.searchBtn, busy: _searching, onPressed: _search),
            ],
          ),
          AnimatedSize(
            duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 220),
            alignment: Alignment.topCenter,
            child: r == null ? const SizedBox(width: double.infinity) : _resultCard(r, ds, t),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(_Search r, DS ds, DText t) {
    final hit = r is _Hit ? r.area : null;
    final (String title, String body) = switch (r) {
      _Empty() => (ds.searchEmptyTitle, ds.searchEmptyBody),
      _Miss() => (ds.searchMissTitle, ds.searchMissBody),
      _BadPin() => (ds.badPinTitle, ds.badPinBody),
      _Failed() => (ds.searchFailed, ''),
      _Hit(:final area) => (
        area.isNamedArea
            ? '${area.label(ds.hindi)}, ${area.cityName}${area.pincode == null ? '' : ' · ${area.pincode}'}'
            : area.pincode != null
            ? ds.pinTitle(area.pincode!, area.label(ds.hindi))
            : area.label(ds.hindi),
        [
          if (area.openSites != null) ds.openRecords(area.openSites!) else ds.coveredCity(area.label(ds.hindi)),
          if (area.lastPass != null) ds.lastPass(DateFormat('d MMM').format(area.lastPass!)),
        ].join(' '),
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        liveRegion: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: DColors.inkRaised,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: hit != null ? DColors.clean : DColors.inkLine, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: t.body(15, weight: FontWeight.w700, color: DColors.paper),
              ),
              if (body.isNotEmpty) Text(body, style: t.body(14, color: DColors.onInkMuted)),
              if (hit?.point != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: DNavLink(
                    label: ds.seeOnMap,
                    size: 14,
                    onPressed: () {
                      ref.read(mapFocusProvider.notifier).set(hit!.point);
                      openShell(context, 'map');
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --- journey ---------------------------------------------------------------------

  static const _stopColors = [DColors.signal, DColors.ink, DColors.filed, DColors.clean];

  Widget _journey(DS ds, DText t, bool wide, double gutter) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    Widget stop(int i) {
      final on = i == _stop;
      return Semantics(
        button: true,
        selected: on,
        child: InkWell(
          key: ValueKey('stop-$i'),
          onTap: () => setState(() => _stop = i),
          child: Container(
            padding: const EdgeInsets.only(top: 18, bottom: 6, right: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: on ? _stopColors[i] : Colors.transparent, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StageRing(progress: (i + 1) / 4, color: _stopColors[i], size: narrow ? 36 : 44),
                const SizedBox(height: 10),
                Text(ds.journeyNames[i], style: t.head(narrow ? 20 : 24, color: on ? DColors.ink : DColors.muted)),
              ],
            ),
          ),
        ),
      );
    }

    return DPage(
      padding: EdgeInsets.fromLTRB(gutter, 96, gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Semantics(header: true, child: Text(ds.journeyH, style: t.head(narrow ? 32 : 44))),
          ),
          const SizedBox(height: 28),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: DColors.rule)),
            ),
            child: Row(children: [for (var i = 0; i < 4; i++) Expanded(child: stop(i))]),
          ),
          const SizedBox(height: 4),
          Semantics(
            liveRegion: true,
            child: AnimatedSwitcher(
              duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 200),
              layoutBuilder: (current, previous) =>
                  Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
              child: DPanel(
                key: ValueKey('stop-text-$_stop-${ds.hindi}'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(DS.journeyTags[_stop], style: DText.mono(12, color: DColors.muted)),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Text(ds.journeyText[_stop], style: t.body(narrow ? 17 : 19)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- India's goal ---------------------------------------------------------------------

  Widget _goal(DS ds, DText t, double gutter) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return DPage(
      padding: EdgeInsets.fromLTRB(gutter, 112, gutter, 0),
      child: Wrap(
        spacing: 40,
        runSpacing: 24,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(ds.goal, style: t.head(narrow ? 28 : 36, height: 1.2)),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '1,048 ',
                        style: DText.mono(44, color: DColors.clean, weight: FontWeight.w500),
                      ),
                      TextSpan(
                        text: '/ 2,476',
                        style: DText.mono(20, color: DColors.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Semantics(
                  label: ds.goalBarLabel,
                  child: Container(
                    height: 10,
                    color: DColors.track,
                    alignment: Alignment.centerLeft,
                    child: const FractionallySizedBox(
                      widthFactor: 1048 / 2476,
                  heightFactor: 1,
                      child: ColoredBox(color: DColors.clean),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(ds.goalNote, style: t.body(14, color: DColors.body)),
                const SizedBox(height: 6),
                Text(ds.goalSource, style: t.body(12, color: DColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- a reason to come back ---------------------------------------------------------

  Widget _follow(DS ds, DText t, double gutter) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final area = _result is _Hit ? (_result as _Hit).area : null;
    final follows = ref.watch(followsProvider).value ?? const <String>{};
    final on = area != null && follows.contains(area.id);
    final passLine = area?.nextPass == null
        ? ds.revisit
        : ds.nextPass(area!.cityName, DateFormat('d MMM').format(area.nextPass!).toUpperCase());

    final button = area == null
        ? DSecondaryButton(label: ds.followFind, onPressed: _findArea)
        : !area.isNamedArea
        ? DSecondaryButton(label: ds.followNamed, onPressed: _findArea)
        : on
        ? DSecondaryButton(
            label: ds.following(area.label(ds.hindi)),
            selected: true,
            onPressed: _followBusy ? null : () => _toggleFollow(area, false),
          )
        : DPrimaryButton(
            label: ds.follow(area.label(ds.hindi)),
            busy: _followBusy,
            onPressed: () => _toggleFollow(area, true),
          );

    return DPage(
      padding: EdgeInsets.fromLTRB(gutter, 112, gutter, 0),
      child: DPanel(
        padding: EdgeInsets.all(narrow ? 24 : 44),
        child: Wrap(
          spacing: 32,
          runSpacing: 24,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ds.followH, style: t.head(narrow ? 28 : 36, height: 1.15)),
                  const SizedBox(height: 10),
                  Text(ds.followBody, style: t.body(17, color: DColors.body)),
                  const SizedBox(height: 10),
                  Text(passLine, style: ds.hindi ? t.body(13, weight: FontWeight.w600) : DText.mono(13)),
                ],
              ),
            ),
            button,
          ],
        ),
      ),
    );
  }

  // --- closing ------------------------------------------------------------------------------

  Widget _closing(DS ds, DText t, double gutter) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return DPage(
      padding: EdgeInsets.fromLTRB(gutter, 112, gutter, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 20,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(ds.closing, style: t.head(narrow ? 24 : 30)),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  DPrimaryButton(label: ds.raise, onPressed: () => openRaise(context)),
                  DSecondaryButton(label: ds.trackYours, onPressed: () => openTrack(context)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: DColors.rule)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(DS.credits, style: t.body(13, color: DColors.muted)),
                Wrap(
                  spacing: 18,
                  children: [
                    DNavLink(
                      label: ds.privacy,
                      onInk: false,
                      size: 13,
                      onPressed: () => _about(ds.privacy, ds.privacyBody),
                    ),
                    DNavLink(label: ds.about, onInk: false, size: 13, onPressed: () => _about(ds.about, ds.aboutBody)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Signs the user in from a bottom sheet; returns when the sheet closes.
Future<void> showSignInSheet(BuildContext context, String reason) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (ctx) => Consumer(
    builder: (ctx, ref, _) {
      // Close the sheet as soon as the sign-in lands.
      ref.listen(meProvider, (_, me) {
        if (me != null && Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
      });
      final hindi = ref.watch(hindiProvider);
      return Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(reason, style: DText(hindi).body(16, weight: FontWeight.w600)),
                const SizedBox(height: 12),
                const AuthForm(),
              ],
            ),
          ),
        ),
      );
    },
  ),
);
