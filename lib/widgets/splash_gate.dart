import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'common.dart' show MvLogo;
import 'wallpaper.dart';

/// How long the launch splash stays up. Tests override it with
/// [Duration.zero] to skip the splash.
final splashDurationProvider = Provider<Duration>((ref) => const Duration(milliseconds: 2800));

const _fade = Duration(milliseconds: 450);

/// Shows the Ikiguzi splash over the app for a few seconds at launch, then
/// fades it away. The app underneath keeps loading meanwhile; the splash only
/// blocks touches while it is up.
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
      if (mounted) setState(() => _phase = _Phase.fading);
    }));
    _timers.add(Timer(shown + _fade, () {
      if (mounted) setState(() => _phase = _Phase.gone);
    }));
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
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
    return MvWallpaper(
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
          child: const MvLogo(size: 64),
        ),
      ),
    );
  }
}
