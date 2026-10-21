import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';

/// The dark teal totals panel from the checkout design: a rounded block with
/// white text that holds the price breakdown and the main button.
class BrandPanel extends StatelessWidget {
  const BrandPanel({super.key, required this.children, this.margin = const EdgeInsets.only(bottom: 14)});
  final List<Widget> children;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: context.isDarkMode ? const Color(0xFF0A4457) : MvColors.brand,
        borderRadius: BorderRadius.circular(MvRadius.sheet),
        boxShadow: const [BoxShadow(color: Color(0x33064F65), blurRadius: 22, offset: Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

/// A label / value line on a [BrandPanel]. [bold] makes it the total.
class PanelRow extends StatelessWidget {
  const PanelRow(this.label, this.value, {super.key, this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: Colors.white.withValues(alpha: bold ? 1 : .78), fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontSize: bold ? 15 : 13))),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: bold ? GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20) : const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Panel heading line ("Order summary").
class PanelTitle extends StatelessWidget {
  const PanelTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
      );
}
