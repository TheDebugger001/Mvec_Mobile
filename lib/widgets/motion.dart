import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Shared motion: durations, curves and the small animated building blocks
/// (press feedback, heart pop, badge bump, skeletons, page transitions).
///
/// Every piece checks the phone's "reduce motion" setting and shows the final
/// state straight away when it is on.
class Motion {
  Motion._();

  static const press = Duration(milliseconds: 110);
  static const release = Duration(milliseconds: 220);
  static const quick = Duration(milliseconds: 180);
  static const base = Duration(milliseconds: 240);

  /// Settles with a slight overshoot, like a spring.
  static const spring = Cubic(.34, 1.45, .64, 1);
  static const out = Curves.easeOutCubic;

  /// True when the device asks for less motion.
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Shrinks its child slightly while a finger is down and springs back on
/// release. It only listens to the pointer, so taps, long presses and
/// scrolling work exactly as before, and the action is never delayed.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.scale = .96, this.enabled = true});
  final Widget child;
  final double scale;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  Offset? _start;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || Motion.reduced(context)) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _start = e.position;
        _set(true);
      },
      // A drag is a scroll, not a press.
      onPointerMove: (e) {
        if (_start != null && (e.position - _start!).distance > 8) _set(false);
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: _down ? Motion.press : Motion.release,
        curve: _down ? Curves.easeOut : Motion.spring,
        child: widget.child,
      ),
    );
  }
}

/// Gives its child a short bounce whenever [value] goes up (cart and wishlist
/// counts). Decreases update quietly.
class BumpOnIncrease extends StatefulWidget {
  const BumpOnIncrease({super.key, required this.value, required this.child});
  final int value;
  final Widget child;

  @override
  State<BumpOnIncrease> createState() => _BumpOnIncreaseState();
}

class _BumpOnIncreaseState extends State<BumpOnIncrease> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween<double>(begin: 1, end: 1.32).chain(CurveTween(curve: Curves.easeOut)), weight: 35),
    TweenSequenceItem(tween: Tween<double>(begin: 1.32, end: 1).chain(CurveTween(curve: Curves.elasticOut)), weight: 65),
  ]).animate(_c);

  @override
  void didUpdateWidget(BumpOnIncrease old) {
    super.didUpdateWidget(old);
    if (widget.value > old.value && !Motion.reduced(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(scale: _scale, child: widget.child);
}

/// Text that slides and fades when its value changes (totals, counts, prices).
class AnimatedValueText extends StatelessWidget {
  const AnimatedValueText(this.text, {super.key, this.style, this.textAlign});
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.reduced(context) ? Duration.zero : Motion.quick,
      switchInCurve: Motion.out,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerRight, children: [...previous, if (current != null) current]),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(position: Tween(begin: const Offset(0, .35), end: Offset.zero).animate(a), child: child),
      ),
      child: Text(text, key: ValueKey(text), style: style, textAlign: textAlign),
    );
  }
}

/// A heart that pops when it turns on and settles back when it turns off.
/// The first switch on shows a tiny burst of dots. It follows [active], which
/// comes from the wishlist itself, so it never shows a save that did not happen.
class HeartPop extends StatefulWidget {
  const HeartPop({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<HeartPop> createState() => _HeartPopState();
}

class _HeartPopState extends State<HeartPop> with TickerProviderStateMixin {
  late final _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 460));
  late final _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween<double>(begin: .7, end: 1.28).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
    TweenSequenceItem(tween: Tween<double>(begin: 1.28, end: 1).chain(CurveTween(curve: Curves.elasticOut)), weight: 60),
  ]).animate(_pop);
  late final _shrink = Tween<double>(begin: .78, end: 1).chain(CurveTween(curve: Motion.spring)).animate(_pop);

  @override
  void initState() {
    super.initState();
    // Start at rest: a heart that is already saved shows at full size.
    _pop.value = 1;
  }

  @override
  void didUpdateWidget(HeartPop old) {
    super.didUpdateWidget(old);
    if (old.active == widget.active || Motion.reduced(context)) return;
    _pop.forward(from: 0);
    if (widget.active) _burst.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _burst,
              builder: (_, __) => _burst.isAnimating ? CustomPaint(painter: _BurstPainter(_burst.value)) : const SizedBox.shrink(),
            ),
          ),
        ),
        ScaleTransition(scale: widget.active ? _scale : _shrink, child: widget.child),
      ],
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final eased = Curves.easeOut.transform(t);
    final r = size.shortestSide * (.45 + .45 * eased);
    final paint = Paint()..color = MvColors.rose.withValues(alpha: (1 - t).clamp(0, 1));
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + i * math.pi / 3;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r, 2.2 * (1 - t * .6), paint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}

/// Grey placeholder with a soft light sweep, shown while real content loads.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height, this.radius = 10});
  final double? width;
  final double? height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final base = mv.surfaceMuted;
    final shine = context.isDarkMode ? mv.border : Colors.white;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final x = -1.5 + 3 * _c.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(x - 1, 0),
              end: Alignment(x + 1, 0),
              colors: [base, shine, base],
              stops: const [.3, .5, .7],
            ),
          ),
        );
      },
    );
  }
}

/// Short fade with a small directional slide between screens. iOS keeps its
/// own transition so the swipe-back gesture still works.
class MvPageTransitionsBuilder extends PageTransitionsBuilder {
  const MvPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    if (Motion.reduced(context)) return child;
    final enter = CurvedAnimation(parent: animation, curve: Motion.out, reverseCurve: Curves.easeInCubic);
    final under = CurvedAnimation(parent: secondaryAnimation, curve: Motion.out);
    return SlideTransition(
      position: Tween(begin: Offset.zero, end: const Offset(-.04, 0)).animate(under),
      child: FadeTransition(
        opacity: enter,
        child: SlideTransition(position: Tween(begin: const Offset(.06, 0), end: Offset.zero).animate(enter), child: child),
      ),
    );
  }
}

/// Slides a column of children in from the side, one after another, the first
/// time it appears (sign-in and sign-up forms). Later rebuilds, such as typing
/// or switching to code login, do not replay it; children added afterwards
/// simply appear.
class SlideInColumn extends StatefulWidget {
  const SlideInColumn({super.key, required this.children, this.crossAxisAlignment = CrossAxisAlignment.stretch, this.from = const Offset(.18, 0)});
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;
  final Offset from;

  @override
  State<SlideInColumn> createState() => _SlideInColumnState();
}

class _SlideInColumnState extends State<SlideInColumn> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final int _count;

  static const _step = 55; // ms between children
  static const _each = 420; // ms for one child

  @override
  void initState() {
    super.initState();
    _count = widget.children.length;
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: _each + _step * (_count - 1).clamp(0, 12)));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _c.value = 1;
    } else if (_c.value == 0 && !_c.isAnimating) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _c.duration!.inMilliseconds;
    return Column(
      crossAxisAlignment: widget.crossAxisAlignment,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          if (i >= _count)
            widget.children[i]
          else
            Builder(builder: (_) {
              final start = (_step * i.clamp(0, 12)) / total;
              final a = CurvedAnimation(parent: _c, curve: Interval(start, (start + _each / total).clamp(0, 1), curve: Motion.out));
              return FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween(begin: widget.from, end: Offset.zero).animate(a), child: widget.children[i]),
              );
            }),
      ],
    );
  }
}
