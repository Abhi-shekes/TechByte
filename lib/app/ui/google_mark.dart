import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The Google "G", drawn in its four brand colours.
///
/// Replaces `Icons.g_mobiledata_rounded` — a Material glyph that was standing
/// in for the Google mark on the only button in the sign-in screen. It read as
/// a placeholder because it was one.
///
/// Painted rather than shipped as an asset because the project bundles no
/// image assets at all. If the official SVG is ever added to `assets/`, prefer
/// it: this is an accurate reconstruction, but the real mark is the real mark.
class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _GoogleMarkPainter()),
    );
  }
}

class _GoogleMarkPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  static double _rad(double degrees) => degrees * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.26;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Clockwise from 11 o'clock. Angles are measured from 3 o'clock, which is
    // how Canvas.drawArc reads them.
    void segment(Color color, double startDeg, double sweepDeg) {
      canvas.drawArc(
        rect,
        _rad(startDeg),
        _rad(sweepDeg),
        false,
        arc..color = color,
      );
    }

    segment(_red, 240, 90); // over the top
    segment(_blue, 330, 55); // upper right, where the bar attaches
    segment(_green, 25, 125); // down the right and along the bottom
    segment(_yellow, 150, 90); // up the left side

    // The crossbar, which is what makes it a G rather than a ring.
    final barTop = size.height / 2 - stroke / 2;
    canvas.drawRect(
      Rect.fromLTRB(
        size.width * 0.5,
        barTop,
        size.width - stroke / 2,
        barTop + stroke,
      ),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
