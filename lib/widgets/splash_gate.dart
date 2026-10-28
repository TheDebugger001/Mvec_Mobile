import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../state/catalog_state.dart';
import '../state/hero_state.dart';
import 'common.dart' show MvLogo;
import 'wallpaper.dart';

/// The shortest the launch splash stays up, so the brand always gets its
/// moment. Tests override it with [Duration.zero] to skip the splash.
final splashDurationProvider = Provider<Duration>((ref) => const Duration(milliseconds: 2500));

/// One piece of start-up preparation the splash waits for. A failing task
/// never blocks the app.
typedef SplashTask = Future<void> Function(WidgetRef ref, BuildContext context);

/// What the home page needs before it can show without anything popping in
/// afterwards: the marketplace data, the hero ads, then the first product
/// pictures decoded into the image cache. Tests override this with an empty
/// list so the splash never touches the network.
final splashTasksProvider = Provider<List<SplashTask>>((ref) => const [_loadCatalog, _loadHeroAds, _warmImages]);

Future<void> _loadCatalog(WidgetRef ref, BuildContext context) async {
  await ref.read(catalogProvider.future);
}

Future<void> _loadHeroAds(WidgetRef ref, BuildContext context) async {
  await ref.read(heroAdsProvider.future);
}

Future<void> _warmImages(WidgetRef ref, BuildContext context) async {
  final catalog = await ref.read(catalogProvider.future);
  final ads = await ref.read(heroAdsProvider.future);
  final urls = {
    for (final p in [...ads, ...catalog.deals.take(6), ...catalog.popular.take(8)]) resolveImageUrl(p.image),
  }..remove('');
  // A slow connection must not hold the splash for long: give the pictures a moment.
  await Future.wait([
    for (final url in urls)
      if (context.mounted) precacheImage(CachedNetworkImageProvider(url), context).catchError((_) {}),
  ]).timeout(const Duration(seconds: 3), onTimeout: () => const []);
}

const _fade = Duration(milliseconds: 450);

/// How long the home page gets to paint its finished content under the splash
/// before the splash fades.
const _settle = Duration(milliseconds: 300);

/// An offline or very slow start-up is never held longer than this.
const _patience = Duration(seconds: 10);

/// Shows the Ikiguzi splash over the app at launch while the home page loads
/// underneath, and fades it only once the products are ready to be seen, so
/// the home page never loads in after the splash. It blocks touches while up.
class SplashGate extends ConsumerStatefulWidget {
  const SplashGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<SplashGate> createState() => _SplashGateState();
}

enum _Phase { showing, fading, gone }

class _SplashGateState extends ConsumerState<SplashGate> {
  late _Phase _phase;
  final _timers = <Timer>[];
  ProviderSubscription<AsyncValue<Object?>>? _keepAds;
  late int _pending;
  bool _minimumElapsed = false;
  bool _gaveUp = false;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    final shown = ref.read(splashDurationProvider);
    if (shown == Duration.zero) {
      _phase = _Phase.gone;
      return;
    }
    _phase = _Phase.showing;
    _timers.add(Timer(shown, () {
      _minimumElapsed = true;
      _maybeFinish();
    }));
    _timers.add(Timer(_patience, () {
      _gaveUp = true;
      _maybeFinish();
    }));

    final tasks = ref.read(splashTasksProvider);
    _pending = tasks.length;
    // Keep the auto-disposed hero ads alive until the home page has taken them.
    if (tasks.isNotEmpty) {
      _keepAds = ref.listenManual(heroAdsProvider, (_, __) {});
    }
    for (final task in tasks) {
      task(ref, context).catchError((_) {}).whenComplete(() {
        _pending--;
        _maybeFinish();
      });
    }
  }

  /// Fades the splash once the minimum time is up and everything is ready (or
  /// start-up is taking too long to wait for).
  void _maybeFinish() {
    if (_finishing || !mounted || !_minimumElapsed) return;
    if (_pending > 0 && !_gaveUp) return;
    _finishing = true;
    _timers.add(Timer(_settle, () {
      if (!mounted) return;
      setState(() => _phase = _Phase.fading);
      _timers.add(Timer(_fade, () {
        if (!mounted) return;
        _keepAds?.close();
        setState(() => _phase = _Phase.gone);
      }));
    }));
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _keepAds?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _Phase.gone) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          ignoring: _phase == _Phase.fading,
          child: AnimatedOpacity(
            opacity: _phase == _Phase.fading ? 0 : 1,
            duration: _fade,
            curve: Curves.easeOut,
            child: const _SplashScreen(),
          ),
        ),
      ],
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final dark = context.isDarkMode;
    // The splash sits above the Navigator, so it has no Material of its own;
    // without one, Text falls back to the yellow double-underline debug style.
    return Material(
      type: MaterialType.transparency,
      child: MvWallpaper(
        child: Center(
          // The same wordmark widget as the top bar, so the font can never differ.
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.scale(scale: .9 + .1 * t, child: child),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _AppTile(),
                const SizedBox(height: 36),
                MvLogo(size: 46, color: mv.accent),
                const SizedBox(height: 6),
                Text(
                  'YOUR MARKETPLACE,\nEVERYTHING',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: mv.accent.withValues(alpha: dark ? .85 : .6),
                    fontSize: 13,
                    height: 1.45,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w400,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The app icon: a rounded teal tile with the smiling shopping bag.
class _AppTile extends StatelessWidget {
  const _AppTile();

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final dark = context.isDarkMode;
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: mv.accent,
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: mv.accent.withValues(alpha: dark ? .4 : .28),
            blurRadius: dark ? 36 : 40,
            offset: Offset(0, dark ? 8 : 18),
          ),
        ],
      ),
      child: const CustomPaint(painter: _BagPainter()),
    );
  }
}

class _BagPainter extends CustomPainter {
  const _BagPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final c = size.center(Offset.zero);
    // Body with a slightly narrower top edge, like the artwork.
    final body =
        Path()
          ..moveTo(c.dx - 22, c.dy - 18)
          ..lineTo(c.dx + 22, c.dy - 18)
          ..lineTo(c.dx + 25, c.dy + 30)
          ..lineTo(c.dx - 25, c.dy + 30)
          ..close();
    canvas.drawPath(body, paint);
    // The folded top edge.
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - 19, c.dy - 18)
        ..lineTo(c.dx - 14, c.dy - 30)
        ..lineTo(c.dx + 14, c.dy - 30)
        ..lineTo(c.dx + 19, c.dy - 18),
      paint,
    );
    // The smile.
    canvas.drawArc(
      Rect.fromCenter(center: Offset(c.dx, c.dy - 2), width: 22, height: 22),
      .35,
      2.45,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_BagPainter old) => false;
}
