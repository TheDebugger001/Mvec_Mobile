import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import 'mv_icon.dart';

/// Light / dark switch, same design as the web app (`ThemeToggle.jsx`): a pill
/// track with a ghost sun on the left and moon on the right, and a round knob
/// that slides from the sun to the moon when dark mode turns on.
class ThemeSwitch extends ConsumerWidget {
  const ThemeSwitch({super.key, this.compact = false});

  /// Slightly smaller track, for the crowded phone top bar.
  final bool compact;

  static const _w = 52.0;
  static const _h = 28.0;
  static const _knob = 22.0;
  static const _travel = 24.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = context.isDarkMode;
    const dur = Duration(milliseconds: 350);
    const curve = Cubic(.4, 1.35, .5, 1);

    final core = Semantics(
      button: true,
      toggled: dark,
      label: dark ? 'Switch to light mode' : 'Switch to dark mode',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(themeModeProvider.notifier).set(dark ? ThemeMode.light : ThemeMode.dark),
        child: SizedBox(
          width: _w + 8,
          height: 40,
          child: Center(
            child: SizedBox(
              width: _w,
              height: _h,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Track
                  Positioned.fill(
                    child: AnimatedContainer(
                      duration: dur,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: dark ? const [Color(0xFF17222C), Color(0xFF2A3550)] : const [Color(0xFFDFF3FB), Color(0xFFFDF0CF)],
                        ),
                        border: Border.all(color: dark ? const Color(0x14FFFFFF) : const Color(0x1411232D)),
                      ),
                    ),
                  ),
                  // Stars (dark only)
                  for (final s in const [(11.0, 8.0, 2.0), (18.0, 18.0, 1.5), (25.0, 10.0, 1.5)])
                    Positioned(
                      left: s.$1,
                      top: s.$2,
                      child: AnimatedOpacity(
                        duration: dur,
                        opacity: dark ? .85 : 0,
                        child: Container(width: s.$3, height: s.$3, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                      ),
                    ),
                  // Ghost sun (left) — visible in dark, where the knob has moved away.
                  Positioned(
                    left: 8,
                    top: (_h - 14) / 2,
                    child: AnimatedOpacity(
                      duration: dur,
                      opacity: dark ? .55 : 0,
                      child: const MvIcon('sun', size: 14, color: Color(0xFFE0A526), strokeWidth: 2),
                    ),
                  ),
                  // Ghost moon (right) — visible in light.
                  Positioned(
                    right: 7,
                    top: (_h - 14) / 2,
                    child: AnimatedOpacity(
                      duration: dur,
                      opacity: dark ? 0 : .75,
                      child: const MvIcon('moon', size: 14, color: Color(0xFF7D8EA0), strokeWidth: 2),
                    ),
                  ),
                  // Knob
                  AnimatedPositioned(
                    duration: dur,
                    curve: curve,
                    left: 3 + (dark ? _travel : 0),
                    top: 3,
                    child: AnimatedContainer(
                      duration: dur,
                      width: _knob,
                      height: _knob,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dark ? const Color(0xFF33405A) : Colors.white,
                        boxShadow: [BoxShadow(color: dark ? const Color(0x73000000) : const Color(0x3811232D), blurRadius: 6, offset: const Offset(0, 2))],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedOpacity(
                            duration: dur,
                            opacity: dark ? 0 : 1,
                            child: AnimatedRotation(
                              duration: dur,
                              turns: dark ? .25 : 0,
                              child: const MvIcon('sun', size: 14, color: Color(0xFFF0A91A), strokeWidth: 2),
                            ),
                          ),
                          AnimatedOpacity(
                            duration: dur,
                            opacity: dark ? 1 : 0,
                            child: AnimatedRotation(
                              duration: dur,
                              turns: dark ? -.055 : -.17,
                              child: const MvIcon('moon', size: 13, color: Color(0xFFC9D6FF), strokeWidth: 2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return compact ? SizedBox(width: 48, height: 40, child: FittedBox(child: core)) : core;
  }
}
