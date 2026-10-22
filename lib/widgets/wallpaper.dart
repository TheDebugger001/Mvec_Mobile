import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Ikiguzi's shopping-doodle wallpaper (the WhatsApp chat-wallpaper idea,
/// drawn with marketplace things instead).
///
/// One 260x260 tile of thin outline doodles is recorded once into a
/// [ui.Picture] and stamped across the screen, so content above it never
/// repaints the pattern. The tile is re-recorded only when the theme colours
/// change (light/dark switch). It carries no text: the "Ikiguzi" wordmark is
/// always the real `MvLogo` widget, so the font cannot differ.
///
/// It is a background layer: it ignores pointer events and sits behind
/// [child]. Used on the launch splash only; the marketplace stays clean.
class MvWallpaper extends StatefulWidget {
  const MvWallpaper({super.key, required this.child});
  final Widget child;

  @override
  State<MvWallpaper> createState() => _MvWallpaperState();
}

class _MvWallpaperState extends State<MvWallpaper> {
  ui.Picture? _tile;
  Color? _ink;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mv = context.mv;
    final dark = context.isDarkMode;
    final ink = mv.textMuted.withValues(alpha: dark ? .17 : .22);
    if (_tile == null || ink != _ink) {
      _ink = ink;
      _record();
    }
  }

  void _record() {
    _tile?.dispose();
    _tile = recordWallpaperTile(ink: _ink!);
  }

  @override
  void dispose() {
    _tile?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.mv.page,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(painter: _WallpaperPainter(_tile!)),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _WallpaperPainter extends CustomPainter {
  _WallpaperPainter(this.tile);
  final ui.Picture tile;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    for (var y = 0.0; y < size.height; y += kWallpaperTile) {
      for (var x = 0.0; x < size.width; x += kWallpaperTile) {
        canvas.save();
        canvas.translate(x, y);
        canvas.drawPicture(tile);
        canvas.restore();
      }
    }
  }

  // The tile instance only changes when the colours do.
  @override
  bool shouldRepaint(_WallpaperPainter old) => !identical(old.tile, tile);
}

/// Side of the repeating square, in logical pixels.
const double kWallpaperTile = 260;

/// One doodle on the 24x24 grid: SVG-style path data plus optional circles.
class _Doodle {
  const _Doodle(this.d, [this.circles = const []]);
  final String d;
  final List<(double, double, double)> circles;
}

const _tshirt = _Doodle('M8 3 3 6l2 4 2.5-1V21h9V9l2.5 1 2-4-5-3c-.5 1.6-2 2.4-4 2.4c-2 0-3.5-.8-4-2.4Z');
const _sneaker = _Doodle('M2 17v-5.5l4.5-1.5 2 2.5h4l3-3 3 2.5c3 .6 5 2 5 4V19H2ZM2 17h20M9.5 13l1.5 1.5M12.5 12l1.5 1.5');
const _cart = _Doodle('M2 4h3l2.6 11h10.2l2.2-8.5H6.4M9 8.5l.9 3.5M13 8.5v3.5M17 8.5l-.9 3.5', [(9.5, 19.2, 1.5), (17, 19.2, 1.5)]);
const _phone = _Doodle('M8 2h8q2 0 2 2v16q0 2-2 2H8q-2 0-2-2V4q0-2 2-2ZM10.5 19h3M10 4.6h4');
const _apple = _Doodle('M12 8.5c-3-2.2-7.2-.6-7.2 4 0 4.2 3 8.5 5.2 8.5 1 0 1.4-.5 2-.5c.5 0 1 .5 2 .5c2.2 0 5.2-4.3 5.2-8.5 0-4.6-4.2-6.2-7.2-4ZM12 8.5c0-2.2 1-3.8 3.2-5M13 4c1.3-.6 2.5-.3 3.3.5');
const _headphones = _Doodle('M4 15v-3c0-5 3.5-8 8-8c4.5 0 8 3 8 8v3M4 14h3.2v6H4ZM16.8 14H20v6h-3.2Z');
const _trousers = _Doodle('M7 3h10l1.2 18h-5.2L12 9.5 11 21H5.8ZM7 6.5h10');
const _dress = _Doodle('M9 3 8.2 9 4 21h16L15.8 9 15 3M9 3q3 3 6 0M8.2 9h7.6M12 9v4');
const _watch = _Doodle('M7 7h10v10H7ZM8.5 7l.8-4.5h5.4L15.5 7M8.5 17l.8 4.5h5.4l.8-4.5M12 9.5V12l2 1.5');
const _bag = _Doodle('M5 8h14l1 13H4ZM9 8V6.2c0-4.2 6-4.2 6 0V8M9.5 12c.3 2 4.7 2 5 0');
const _laptop = _Doodle('M5 6h14v9.5H5ZM2 18h20l-1.6 2.2H3.6ZM9.5 18h5');
const _glasses = _Doodle('M10.5 13.5c.9-1 2.1-1 3 0M2.5 13.5l1.8-6M21.5 13.5l-1.8-6', [(6.5, 14.5, 3.9), (17.5, 14.5, 3.9)]);
const _box = _Doodle('M3 7l9-4 9 4v10l-9 4-9-4ZM3 7l9 4 9-4M12 11v10M7.5 5l9 4');
const _chair = _Doodle('M7.5 3h9l.8 9H6.7ZM5.5 12h13v3.2h-13ZM7 15.2V21M17 15.2V21M7.5 7.5h9');
const _tag = _Doodle('M3 3h8.2l9.8 9.8-8.2 8.2L3 11.2Z', [(7.3, 7.3, 1.3)]);
const _ring = _Doodle('M7 4h10l4 5-9 12L3 9ZM3 9h18M9 4l-1.2 5L12 21M15 4l1.2 5L12 21');
const _bottle = _Doodle('M10 2.5h4v3.2c2 1 3 2.5 3 4.8V19q0 2.5-2.5 2.5h-5Q7 21.5 7 19v-8.5c0-2.3 1-3.8 3-4.8ZM7 12h10M7 17h10');

class _Placed {
  const _Placed(this.doodle, this.x, this.y, this.turn, [this.scale = 1.12]);
  final _Doodle doodle;
  final double x;
  final double y;
  final double turn; // radians
  final double scale;
}

// Hand-placed so the tile has no rows or columns, and no doodle comes within
// a few pixels of the tile edge (the pattern stays seamless when repeated).
const _layout = <_Placed>[
  _Placed(_tshirt, 34, 30, -.22),
  _Placed(_sneaker, 106, 26, .12),
  _Placed(_cart, 178, 36, -.12),
  _Placed(_phone, 234, 30, .24, 1.0),
  _Placed(_chair, 28, 94, .1, 1.05),
  _Placed(_apple, 72, 92, .2, 1.0),
  _Placed(_phone, 122, 144, -.3, 0.95),
  _Placed(_headphones, 142, 90, -.2),
  _Placed(_trousers, 208, 98, .16, 1.05),
  _Placed(_dress, 30, 152, -.12),
  _Placed(_box, 190, 154, -.14, 1.0),
  _Placed(_watch, 238, 160, .2, 0.95),
  _Placed(_tag, 74, 186, -.25, 1.0),
  _Placed(_ring, 150, 190, .15, 1.0),
  _Placed(_bag, 38, 226, .1),
  _Placed(_laptop, 108, 226, -.1),
  _Placed(_glasses, 180, 224, .1),
  _Placed(_bottle, 232, 214, -.2, 1.0),
];

/// Small plus signs and dots that fill the gaps between doodles.
const _sparkles = <(double, double)>[(64, 56), (150, 54), (214, 64), (180, 130), (62, 126), (112, 190), (212, 188), (16, 190), (250, 120), (120, 62)];

/// Records the tile. Public so tests can render it.
ui.Picture recordWallpaperTile({required Color ink}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, kWallpaperTile, kWallpaperTile));
  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.15
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = ink;

  for (final p in _layout) {
    canvas.save();
    canvas.translate(p.x, p.y);
    canvas.rotate(p.turn);
    canvas.scale(p.scale);
    canvas.translate(-12, -12);
    final path = _parsePath(p.doodle.d);
    for (final (cx, cy, r) in p.doodle.circles) {
      path.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    }
    // The stroke is in grid units, so divide the scale back out to keep one weight across all doodles.
    canvas.drawPath(path, line..strokeWidth = 1.15 / p.scale);
    canvas.restore();
  }

  line.strokeWidth = 1.1;
  for (final (x, y) in _sparkles) {
    if ((x + y).toInt().isEven) {
      canvas.drawLine(Offset(x - 3, y), Offset(x + 3, y), line);
      canvas.drawLine(Offset(x, y - 3), Offset(x, y + 3), line);
    } else {
      canvas.drawCircle(Offset(x, y), 1.6, line);
    }
  }

  return recorder.endRecording();
}

// ─── Minimal SVG path-data parser (M L H V C Q Z, absolute and relative) ─────

final _tokens = RegExp(r'[MmLlHhVvCcQqZz]|-?(?:\d+\.?\d*|\.\d+)');

Path _parsePath(String d) {
  final path = Path();
  final t = _tokens.allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  var cmd = 'M';
  double cx = 0, cy = 0, sx = 0, sy = 0;
  double num() => double.parse(t[i++]);
  bool isCmd(String s) => RegExp(r'^[A-Za-z]$').hasMatch(s);

  while (i < t.length) {
    if (isCmd(t[i])) cmd = t[i++];
    final rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        final x = num() + (rel ? cx : 0), y = num() + (rel ? cy : 0);
        path.moveTo(x, y);
        cx = sx = x;
        cy = sy = y;
        cmd = rel ? 'l' : 'L'; // extra pairs after M are line-tos
      case 'L':
        cx = num() + (rel ? cx : 0);
        cy = num() + (rel ? cy : 0);
        path.lineTo(cx, cy);
      case 'H':
        cx = num() + (rel ? cx : 0);
        path.lineTo(cx, cy);
      case 'V':
        cy = num() + (rel ? cy : 0);
        path.lineTo(cx, cy);
      case 'C':
        final x1 = num() + (rel ? cx : 0), y1 = num() + (rel ? cy : 0);
        final x2 = num() + (rel ? cx : 0), y2 = num() + (rel ? cy : 0);
        final x = num() + (rel ? cx : 0), y = num() + (rel ? cy : 0);
        path.cubicTo(x1, y1, x2, y2, x, y);
        cx = x;
        cy = y;
      case 'Q':
        final x1 = num() + (rel ? cx : 0), y1 = num() + (rel ? cy : 0);
        final x = num() + (rel ? cx : 0), y = num() + (rel ? cy : 0);
        path.quadraticBezierTo(x1, y1, x, y);
        cx = x;
        cy = y;
      case 'Z':
        path.close();
        cx = sx;
        cy = sy;
    }
  }
  return path;
}
