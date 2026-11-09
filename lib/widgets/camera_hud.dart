import 'package:flutter/material.dart';
import '../theme.dart';

class CameraHud extends StatelessWidget {
  final String filmCode;
  final String focalMm;
  final double evValue;
  final int shotsRemaining;
  final bool showGrid;

  const CameraHud({
    super.key,
    required this.filmCode,
    required this.focalMm,
    required this.evValue,
    required this.shotsRemaining,
    required this.showGrid,
  });

  @override
  Widget build(BuildContext context) {
    final ev = '${evValue >= 0 ? '+' : ''}${evValue.toStringAsFixed(1)}';
    return IgnorePointer(
      child: Stack(
        children: [
          if (showGrid) CustomPaint(size: Size.infinite, painter: _GridPainter()),
          CustomPaint(size: Size.infinite, painter: _CornerMarksPainter()),

          // Top-left: FUJI • 35MM
          Positioned(
            left: 22,
            top: 22,
            child: _Badge(
              child: Text(
                'FUJI • $focalMm',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ),
          ),

          // Bottom row
          Positioned(
            left: 22,
            right: 22,
            bottom: 22,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _Badge(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const RedDot(size: 7),
                        const SizedBox(width: 6),
                        _txt(filmCode),
                      ]),
                    ),
                    const SizedBox(width: 6),
                    _Badge(child: _txt('EV $ev')),
                    const SizedBox(width: 6),
                    _Badge(child: _txt('WB 5500K')),
                  ],
                ),
                _Badge(
                  accent: true,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.camera_roll_outlined, size: 11, color: Colors.white),
                    const SizedBox(width: 4),
                    Text('$shotsRemaining',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _txt(String s) => Text(
        s,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      );
}

class _Badge extends StatelessWidget {
  final Widget child;
  final bool accent;
  const _Badge({required this.child, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(150),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: accent ? AppColors.red : Colors.white.withAlpha(30),
          width: 0.8,
        ),
      ),
      child: child,
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = Colors.white.withAlpha(40)
      ..strokeWidth = 0.6;
    canvas.drawLine(Offset(s.width / 3, 0), Offset(s.width / 3, s.height), p);
    canvas.drawLine(Offset(s.width * 2 / 3, 0), Offset(s.width * 2 / 3, s.height), p);
    canvas.drawLine(Offset(0, s.height / 3), Offset(s.width, s.height / 3), p);
    canvas.drawLine(Offset(0, s.height * 2 / 3), Offset(s.width, s.height * 2 / 3), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CornerMarksPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = Colors.white.withAlpha(140)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const m = 12.0, l = 18.0;
    final w = s.width, h = s.height;
    final path = Path()
      ..moveTo(m, m + l)..lineTo(m, m)..lineTo(m + l, m)
      ..moveTo(w - m - l, m)..lineTo(w - m, m)..lineTo(w - m, m + l)
      ..moveTo(m, h - m - l)..lineTo(m, h - m)..lineTo(m + l, h - m)
      ..moveTo(w - m - l, h - m)..lineTo(w - m, h - m)..lineTo(w - m, h - m - l);
    canvas.drawPath(path, p);

    // Tiny centre cross
    final c = Offset(w / 2, h / 2);
    final cp = Paint()
      ..color = Colors.white.withAlpha(90)
      ..strokeWidth = 1;
    canvas.drawLine(c.translate(-6, 0), c.translate(6, 0), cp);
    canvas.drawLine(c.translate(0, -6), c.translate(0, 6), cp);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}