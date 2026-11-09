import 'package:flutter/material.dart';

class AppColors {
  static const red = Color(0xFFE02A1F);
  static const redBright = Color(0xFFFF5242);
  static const redDeep = Color(0xFF800E0A);
  static const orangeLcd = Color(0xFFFF7A18);
  static const panel = Color(0xFF121212);
  static const panelHigh = Color(0xFF1C1C1C);
  static const stroke = Color(0x1FFFFFFF);
}

/// Small glossy red dot used in place of the 🔴 emoji.
class RedDot extends StatelessWidget {
  final double size;
  const RedDot({super.key, this.size = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [AppColors.redBright, AppColors.red, AppColors.redDeep],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(color: AppColors.red.withAlpha(120), blurRadius: size * 0.9),
        ],
      ),
    );
  }
}