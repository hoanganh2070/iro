import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/film_model.dart';
import '../theme.dart';

class VintageShutterBar extends StatelessWidget {
  final Uint8List? lastThumb;
  final bool isShooting;
  final FilmModel currentFilm;
  final VoidCallback onCapture;
  final VoidCallback onOpenShelf;
  final VoidCallback onOpenGallery;

  const VintageShutterBar({
    super.key,
    required this.lastThumb,
    required this.isShooting,
    required this.currentFilm,
    required this.onCapture,
    required this.onOpenShelf,
    required this.onOpenGallery,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Gallery thumbnail
          _SideButton(
            label: 'GALLERY',
            onTap: onOpenGallery,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.panelHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24, width: 1.2),
                image: lastThumb != null
                    ? DecorationImage(
                        image: ResizeImage(MemoryImage(lastThumb!), width: 180),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: lastThumb == null
                  ? const Icon(Icons.photo_library_outlined, color: Colors.white30, size: 22)
                  : null,
            ),
          ),

          // Shutter button
          GestureDetector(
            onTap: isShooting ? null : onCapture,
            child: AnimatedScale(
              scale: isShooting ? 0.92 : 1.0,
              duration: const Duration(milliseconds: 90),
              child: Container(
                width: 92,
                height: 92,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.red.withAlpha(isShooting ? 20 : 70),
                      blurRadius: 24,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: CustomPaint(painter: _MechanicalShutterPainter(isShooting)),
                ),
              ),
            ),
          ),

          // Film roll
          _SideButton(
            label: 'FILM',
            onTap: onOpenShelf,
            child: Container(
              width: 54,
              height: 54,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: AppColors.panelHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24, width: 1.2),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.asset(
                    currentFilm.imagePath,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.movie_creation_outlined, color: Colors.white70),
                  ),
                  Positioned(
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(210),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        currentFilm.id,
                        style: const TextStyle(
                            fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  final Widget child;
  final String label;
  final VoidCallback onTap;
  const _SideButton({required this.child, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MechanicalShutterPainter extends CustomPainter {
  final bool busy;
  const _MechanicalShutterPainter(this.busy);

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2;

    // Outer knurled metal ring
    final metalRing = Paint()
      ..shader = const SweepGradient(
        colors: [
          Color(0xFFAAAAAF),
          Color(0xFFEBEBEF),
          Color(0xFF707075),
          Color(0xFFD4D4D8),
          Color(0xFF88888D),
          Color(0xFFEBEBEF),
          Color(0xFFAAAAAF),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, metalRing);

    // 72 knurling ticks
    final tick = Paint()
      ..color = const Color(0x66000000)
      ..strokeWidth = 1.0;
    const n = 72;
    for (var i = 0; i < n; i++) {
      final a = 2 * math.pi * i / n;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r - 6), c + d * (r - 0.5), tick);
    }

    // Black gasket
    canvas.drawCircle(c, r - 7.5, Paint()..color = const Color(0xFF0C0C0C));

    // Fuji-red centre button
    final innerR = r - 12;
    final redBtn = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.35, -0.45),
        radius: 1.1,
        colors: [Color(0xFFFF5242), Color(0xFFE02A1F), Color(0xFF800E0A)],
        stops: [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: innerR));
    canvas.drawCircle(c, innerR, redBtn);

    // Curved highlight
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: innerR - 3),
      math.pi * 1.1,
      math.pi * 0.5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withAlpha(100),
    );

    if (busy) {
      canvas.drawCircle(c, innerR, Paint()..color = Colors.black54);
    }
  }

  @override
  bool shouldRepaint(covariant _MechanicalShutterPainter oldDelegate) =>
      oldDelegate.busy != busy;
}