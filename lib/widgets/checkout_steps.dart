import 'package:flutter/material.dart';

import '../core/theme.dart';

/// "Cart → Checkout → Payment" progress, as in the checkout design: finished
/// steps are filled teal with a tick, the current step is ringed, the rest are
/// outlined. Purely a position indicator; it does not navigate.
class CheckoutSteps extends StatelessWidget {
  const CheckoutSteps({super.key, required this.current});

  /// 0 = Cart, 1 = Checkout, 2 = Payment, 3 = everything done.
  final int current;

  static const _labels = ['Cart', 'Checkout', 'Payment'];

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return Semantics(
      label: current >= _labels.length ? 'All steps complete' : 'Step ${current + 1} of ${_labels.length}: ${_labels[current]}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _labels.length; i++) ...[
              _Step(label: _labels[i], done: i < current, active: i == current),
              if (i < _labels.length - 1)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 11, left: 4, right: 4),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 2,
                      decoration: BoxDecoration(color: i < current ? mv.accent : mv.border, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.done, required this.active});
  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return SizedBox(
      width: 62,
      child: Column(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? mv.accent : mv.surface,
              border: Border.all(color: done || active ? mv.accent : mv.border, width: active ? 6 : 1.6),
            ),
            child: done ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
          ),
          const SizedBox(height: 5),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w800 : FontWeight.w600, color: active || done ? mv.text : mv.textMuted)),
        ],
      ),
    );
  }
}
