import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/d_strings.dart';
import '../theme/drishti_theme.dart';

/// True when the platform asks for less motion.
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

// ---------------------------------------------------------------------------
// The mark: an eye (vesica) with a square amber pupil, a satellite pixel.
// ---------------------------------------------------------------------------

class DrishtiMark extends StatelessWidget {
  const DrishtiMark({super.key, this.size = 32, this.onInk = false});
  final double size;
  final bool onInk;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _MarkPainter(onInk ? DColors.paper : DColors.ink)),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.line);
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 32;
    final eye = Path()
      ..moveTo(3 * k, 16 * k)
      ..quadraticBezierTo(16 * k, 4 * k, 29 * k, 16 * k)
      ..quadraticBezierTo(16 * k, 28 * k, 3 * k, 16 * k)
      ..close();
    canvas.drawPath(
      eye,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8 * k
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawRect(Rect.fromLTWH(12.6 * k, 12.6 * k, 6.8 * k, 6.8 * k), Paint()..color = DColors.signal);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.line != line;
}

class DrishtiWordmark extends StatelessWidget {
  const DrishtiWordmark({super.key, this.onInk = false});
  final bool onInk;

  @override
  Widget build(BuildContext context) {
    final c = onInk ? DColors.paper : DColors.ink;
    return Semantics(
      label: 'Drishti',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DrishtiMark(onInk: onInk),
          const SizedBox(width: 10),
          Text('Drishti', style: const DText(false).head(23, color: c)),
          const SizedBox(width: 8),
          Text('दृष्टि', style: const DText(true).head(22, color: onInk ? DColors.onInkFaint : DColors.muted)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stages: one ring and one stamp, the same everywhere.
// ---------------------------------------------------------------------------

Color stageColor(String stage) => switch (stage) {
  'in_progress' || 'scheduled' => DColors.filed,
  'resolved' || 'proven_clean' => DColors.clean,
  'reopened' => DColors.fire,
  _ => DColors.ink,
};

/// The stamp pairs a shape with a word so it reads without colour.
String stageGlyph(String stage) => switch (stage) {
  'in_progress' || 'scheduled' => '➤',
  'resolved' => '●',
  'proven_clean' => '✓',
  'reopened' => '▲',
  'note' => '·',
  _ => '■',
};

class StageStamp extends StatelessWidget {
  const StageStamp(this.stage, {super.key, required this.ds, this.small = false});
  final String stage;
  final DS ds;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = stageColor(stage);
    final solid = stage == 'proven_clean';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: small ? 2 : 3),
      decoration: BoxDecoration(
        color: solid ? c : Colors.transparent,
        border: Border.all(color: c, width: 1.5),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        '${stageGlyph(stage)} ${ds.stamp(stage)}',
        style: DText(ds.hindi)
            .body(small ? 11 : 12, color: solid ? Colors.white : c, weight: FontWeight.w700, height: 1.2),
      ),
    );
  }
}

class StageRing extends StatelessWidget {
  const StageRing({super.key, required this.progress, required this.color, this.size = 44, this.label});
  final double progress;
  final Color color;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress),
      duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _RingPainter(v, color)),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.1;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - stroke);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = DColors.track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0, 1),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}

// ---------------------------------------------------------------------------
// Buttons with feedback that means something.
// ---------------------------------------------------------------------------

/// Hover, focus and press state for a custom control, with keyboard support.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.onPressed, required this.builder, this.label, this.onHoverStart});
  final VoidCallback? onPressed;
  final String? label;
  final VoidCallback? onHoverStart;
  final Widget Function(BuildContext context, bool hover, bool focus, bool down) builder;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _hover = false;
  bool _focus = false;
  bool _down = false;

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final scale = _down && !reduceMotion(context) ? 0.97 : 1.0;
    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      excludeSemantics: widget.label != null,
      onTap: widget.onPressed,
      child: FocusableActionDetector(
        enabled: _enabled,
        mouseCursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) {
          if (v && !_hover && _enabled) widget.onHoverStart?.call();
          setState(() => _hover = v);
        },
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: _enabled ? (_) => setState(() => _down = false) : null,
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 120),
            child: widget.builder(context, _hover && _enabled, _focus, _down),
          ),
        ),
      ),
    );
  }
}

/// The one action that matters on a screen: amber. On hover a band of light
/// crosses it once, like a satellite pass; pressing tightens it.
class DPrimaryButton extends StatefulWidget {
  const DPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.expand = false,
    this.height = 54,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool expand;
  final double height;

  @override
  State<DPrimaryButton> createState() => _DPrimaryButtonState();
}

class _DPrimaryButtonState extends State<DPrimaryButton> with SingleTickerProviderStateMixin {
  late final _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hindi = Localizations.maybeLocaleOf(context)?.languageCode == 'hi';
    final enabled = widget.onPressed != null && !widget.busy;
    return _Pressable(
      onPressed: enabled ? widget.onPressed : null,
      label: widget.label,
      onHoverStart: () {
        if (!reduceMotion(context)) _sweep.forward(from: 0);
      },
      builder: (context, hover, focus, down) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: widget.height,
          width: widget.expand ? double.infinity : null,
          decoration: BoxDecoration(
            color: enabled ? DColors.signal : DColors.signal.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              if (hover || focus || down)
                BoxShadow(
                  color: DColors.signal.withValues(alpha: focus ? 0.55 : 0.28),
                  spreadRadius: down ? 3 : 5,
                ),
            ],
          ),
          child: ClipRect(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _sweep,
                    builder: (_, _) => _sweep.isAnimating
                        ? FractionalTranslation(
                            translation: Offset(-1.3 + 3.9 * Curves.easeInOut.transform(_sweep.value), 0),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: 0.45,
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Color(0x00FFFFFF), Color(0x99FFFFFF), Color(0x00FFFFFF)],
                                  ),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: widget.busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: DColors.ink),
                        )
                      : Text(
                          widget.label,
                          textAlign: TextAlign.center,
                          style: DText(hindi).body(16, weight: FontWeight.w700, height: 1.2),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The second choice: an outline that fills from the left on hover.
class DSecondaryButton extends StatelessWidget {
  const DSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.onInk = false,
    this.height = 54,
    this.expand = false,
    this.selected = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool onInk;
  final double height;
  final bool expand;

  /// A toggle that is on keeps the filled look.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final hindi = Localizations.maybeLocaleOf(context)?.languageCode == 'hi';
    final fg = onInk ? DColors.paper : DColors.ink;
    final fillFg = onInk ? DColors.ink : DColors.paper;
    final dur = reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 350);
    return _Pressable(
      onPressed: onPressed,
      label: label,
      builder: (context, hover, focus, down) {
        final filled = hover || selected;
        return Container(
          height: height,
          width: expand ? double.infinity : null,
          decoration: BoxDecoration(
            border: Border.all(color: fg.withValues(alpha: onPressed == null ? 0.4 : 1), width: 1.5),
            borderRadius: BorderRadius.circular(2),
            boxShadow: [if (focus) BoxShadow(color: DColors.signal.withValues(alpha: 0.6), spreadRadius: 3)],
          ),
          child: ClipRect(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedFractionallySizedBox(
                      duration: dur,
                      curve: Curves.easeOut,
                      widthFactor: filled ? 1 : 0,
                      heightFactor: 1,
                      child: ColoredBox(color: fg),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: AnimatedDefaultTextStyle(
                    duration: dur,
                    style: DText(hindi).body(16, weight: FontWeight.w600, height: 1.2, color: filled ? fillFg : fg),
                    child: Text(label, textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A text link whose amber underline grows in on hover or focus.
class DNavLink extends StatelessWidget {
  const DNavLink({super.key, required this.label, required this.onPressed, this.onInk = true, this.size = 15});
  final String label;
  final VoidCallback onPressed;
  final bool onInk;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hindi = Localizations.maybeLocaleOf(context)?.languageCode == 'hi';
    return _Pressable(
      onPressed: onPressed,
      label: label,
      builder: (context, hover, focus, down) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                label,
                style: DText(hindi)
                    .body(size, weight: FontWeight.w500, color: onInk ? DColors.paper : DColors.ink, height: 1.3),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedFractionallySizedBox(
                  duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 250),
                  widthFactor: hover || focus ? 1 : 0,
                  child: Container(height: 2, color: DColors.signal),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// EN / हिं switch.
class LanguageSwitch extends StatelessWidget {
  const LanguageSwitch({super.key, required this.hindi, required this.onChanged, this.onInk = true});
  final bool hindi;
  final ValueChanged<bool> onChanged;
  final bool onInk;

  @override
  Widget build(BuildContext context) {
    Widget seg(String text, bool on, bool toHindi, String label) => Semantics(
      button: true,
      selected: on,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onChanged(toHindi),
        child: Container(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 40),
          alignment: Alignment.center,
          color: on ? (onInk ? DColors.paper : DColors.ink) : Colors.transparent,
          child: Text(
            text,
            style: DText(toHindi).body(
              14,
              weight: FontWeight.w600,
              color: on ? (onInk ? DColors.ink : DColors.paper) : (onInk ? DColors.onInkMuted : DColors.muted),
            ),
          ),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: onInk ? DColors.inkLine : DColors.rule),
        borderRadius: BorderRadius.circular(2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [seg('EN', !hindi, false, 'English'), seg('हिं', hindi, true, 'हिंदी')],
      ),
    );
  }
}

/// Monospace tag on imagery: a date, a measurement, a coordinate.
class Telemetry extends StatelessWidget {
  const Telemetry(this.text, {super.key, this.background = const Color(0xC714213D), this.color = DColors.paper});
  final String text;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    color: background,
    child: Text(text, style: DText.mono(11, color: color)),
  );
}

// ---------------------------------------------------------------------------
// Before / after: drag to compare two passes over one place.
// ---------------------------------------------------------------------------

/// An illustration (not real imagery) of one site on two passes. The left is
/// the earlier pass with the detected heap outlined; drag right to reveal the
/// later, clean pass. A single scan line crosses once when it first appears.
class BeforeAfter extends StatefulWidget {
  const BeforeAfter({super.key, required this.ds, this.initial = 0.5});
  final DS ds;
  final double initial;

  @override
  State<BeforeAfter> createState() => _BeforeAfterState();
}

class _BeforeAfterState extends State<BeforeAfter> with SingleTickerProviderStateMixin {
  late double _split = widget.initial;
  // 300 ms of stillness, then the 2.6 s pass. One controller, so nothing
  // outlives the widget.
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 2900));
  final _focus = FocusNode(debugLabel: 'before-after');
  bool _focused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intro.status == AnimationStatus.dismissed) {
      if (reduceMotion(context)) {
        _intro.value = 1;
      } else {
        _intro.forward();
      }
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _set(double v) => setState(() => _split = v.clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    return Semantics(
      slider: true,
      label: ds.sliderLabel,
      value: '${(_split * 100).round()}%',
      increasedValue: '${((_split + 0.1).clamp(0, 1) * 100).round()}%',
      decreasedValue: '${((_split - 0.1).clamp(0, 1) * 100).round()}%',
      onIncrease: () => _set(_split + 0.1),
      onDecrease: () => _set(_split - 0.1),
      child: Focus(
        focusNode: _focus,
        onFocusChange: (v) => setState(() => _focused = v),
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
          if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _set(_split - 0.05);
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
            _set(_split + 0.05);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AspectRatio(
          aspectRatio: 5 / 4,
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              void drag(Offset local) => _set(local.dx / w);
              return MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  key: const ValueKey('before-after-drag'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) {
                    _focus.requestFocus();
                    drag(d.localPosition);
                  },
                  onHorizontalDragUpdate: (d) => drag(d.localPosition),
                  child: Container(
                    decoration: BoxDecoration(border: _focused ? Border.all(color: DColors.signal, width: 3) : null),
                    child: ClipRect(
                      child: AnimatedBuilder(
                        animation: _intro,
                        builder: (context, _) {
                          final t = ((_intro.value * 2900 - 300) / 2600).clamp(0.0, 1.0);
                          final scan = (t / 0.85).clamp(0.0, 1.0);
                          final reveal = ((t - 0.65) / 0.2).clamp(0.0, 1.0);
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              CustomPaint(painter: _ScenePainter(after: false, reveal: reveal)),
                              ClipRect(
                                clipper: _FromLeft(_split),
                                child: CustomPaint(painter: _ScenePainter(after: true, reveal: 1)),
                              ),
                              // Labels
                              const Positioned(left: 12, top: 12, child: Telemetry('12 SEP 2026')),
                              Positioned(
                                left: w * 0.34,
                                top: box.maxHeight * 0.40 - 26,
                                child: Opacity(
                                  opacity: reveal,
                                  child: _split < 0.34
                                      ? const SizedBox.shrink()
                                      : const Telemetry(
                                          '2,400 m² · 0.91',
                                          background: DColors.signal,
                                          color: DColors.ink,
                                        ),
                                ),
                              ),
                              Positioned(
                                right: 12,
                                top: 12,
                                child: Telemetry(
                                  '21 OCT 2026 · ${ds.clean}',
                                  background: DColors.clean,
                                  color: Colors.white,
                                ),
                              ),
                              // The one pass
                              if (scan > 0 && scan < 1)
                                Positioned(
                                  left: w * scan - 1,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 2,
                                    decoration: BoxDecoration(
                                      color: DColors.signal,
                                      boxShadow: [
                                        BoxShadow(
                                          color: DColors.signal.withValues(alpha: 0.55),
                                          blurRadius: 14,
                                          spreadRadius: 3,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              // Handle
                              Positioned(
                                left: w * _split - 1,
                                top: 0,
                                bottom: 0,
                                child: const IgnorePointer(
                                  child: SizedBox(width: 2, child: ColoredBox(color: DColors.paper)),
                                ),
                              ),
                              Positioned(
                                left: w * _split - 22,
                                top: box.maxHeight / 2 - 22,
                                child: IgnorePointer(
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: const BoxDecoration(color: DColors.paper, shape: BoxShape.circle),
                                    child: const Icon(Icons.code, color: DColors.ink, size: 22),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Clips to everything right of [split] (0 to 1).
class _FromLeft extends CustomClipper<Rect> {
  _FromLeft(this.split);
  final double split;
  @override
  Rect getClip(Size size) => Rect.fromLTRB(size.width * split, 0, size.width, size.height);
  @override
  bool shouldReclip(_FromLeft old) => old.split != split;
}

/// A stylised 10 m/px tile: fields, a river, two roads and, before, a heap.
class _ScenePainter extends CustomPainter {
  _ScenePainter({required this.after, required this.reveal});
  final bool after;
  final double reveal;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = after ? const Color(0xFF5E6E55) : const Color(0xFF545C4E));
    void blob(double x, double y, double r, Color c) => canvas.drawCircle(
      Offset(w * x, h * y),
      r * w,
      Paint()
        ..shader = RadialGradient(colors: [c, c.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: Offset(w * x, h * y), radius: r * w)),
    );
    blob(0.20, 0.25, 0.22, const Color(0xFF4B5A48));
    blob(0.80, 0.78, 0.20, const Color(0xFF4E5C4A));
    blob(0.75, 0.20, 0.18, const Color(0xFF59604F));
    if (after) {
      blob(0.48, 0.58, 0.30, const Color(0xFF6E9A66));
    } else {
      blob(0.48, 0.58, 0.26, const Color(0xFF8A847A));
      blob(0.47, 0.57, 0.12, const Color(0xFF7A746B));
    }
    final river = Path()
      ..moveTo(-0.02 * w, 0.825 * h)
      ..cubicTo(0.18 * w, 0.75 * h, 0.32 * w, 0.875 * h, 0.52 * w, 0.80 * h)
      ..cubicTo(0.72 * w, 0.725 * h, 0.84 * w, 0.65 * h, 1.04 * w, 0.71 * h);
    canvas.drawPath(
      river,
      Paint()
        ..color = const Color(0xFF3F6E86)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.02
        ..strokeCap = StrokeCap.round,
    );
    final road = Paint()
      ..color = const Color(0xFF6C6F68)
      ..strokeWidth = w * 0.01;
    canvas.drawLine(Offset(0, 0.30 * h), Offset(w, 0.375 * h), road);
    canvas.drawLine(Offset(0.36 * w, 0), Offset(0.42 * w, h), road..strokeWidth = w * 0.008);

    final box = Rect.fromLTWH(0.34 * w, 0.40 * h, 0.28 * w, 0.30 * h);
    if (after) {
      _dashedRect(canvas, box, const Color(0xFFCDEBD8));
    } else if (reveal > 0) {
      final s = 1 + 0.18 * (1 - reveal);
      final r = Rect.fromCenter(center: box.center, width: box.width * s, height: box.height * s);
      canvas.drawRect(r, Paint()..color = DColors.signal.withValues(alpha: 0.18 * reveal));
      canvas.drawRect(
        r,
        Paint()
          ..color = DColors.signal.withValues(alpha: reveal)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  void _dashedRect(Canvas canvas, Rect r, Color c) {
    final p = Paint()
      ..color = c
      ..strokeWidth = 2;
    const dash = 6.0, gap = 4.0;
    void line(Offset a, Offset b) {
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (var d = 0.0; d < len; d += dash + gap) {
        canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, len), p);
      }
    }

    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.after != after || old.reveal != reveal;
}

// ---------------------------------------------------------------------------
// Small pieces
// ---------------------------------------------------------------------------

/// A white panel with a hairline border: the record's paper.
class DPanel extends StatelessWidget {
  const DPanel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.leftRule});
  final Widget child;
  final EdgeInsets padding;

  /// An inset bar that marks state (for example overdue), never decoration.
  final Color? leftRule;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: DColors.surface,
      border: Border(
        top: const BorderSide(color: DColors.rule),
        right: const BorderSide(color: DColors.rule),
        bottom: const BorderSide(color: DColors.rule),
        left: BorderSide(color: leftRule ?? DColors.rule, width: leftRule == null ? 1 : 4),
      ),
    ),
    child: child,
  );
}

/// Section label inside a form.
class DLabel extends StatelessWidget {
  const DLabel(this.text, {super.key, this.hindi = false});
  final String text;
  final bool hindi;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: DText(hindi).body(13, weight: FontWeight.w700, color: DColors.body),
  );
}

/// Centres content at a readable width.
class DPage extends StatelessWidget {
  const DPage({
    super.key,
    required this.child,
    this.maxWidth = 1240,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });
  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(padding: padding, child: child),
    ),
  );
}
