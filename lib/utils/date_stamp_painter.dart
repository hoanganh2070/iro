import 'package:flutter/material.dart';

class DateStampPainter {
  static const Color ledOrange = Color(0xFFFF6500);

  static String getFormattedDate(DateTime time) {
    final yr = (time.year % 100).toString().padLeft(2, '0');
    final mo = time.month.toString().padLeft(2, '0');
    final da = time.day.toString().padLeft(2, '0');
    final hr = time.hour.toString().padLeft(2, '0');
    final mi = time.minute.toString().padLeft(2, '0');
    return "'$yr  $mo  $da  $hr:$mi";
  }

  static void drawStamp(Canvas canvas, Size size, DateTime time) {
    final text = getFormattedDate(time);
    final fontSize = size.shortestSide * 0.038;

    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'Courier',
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.0,
        color: ledOrange,
        shadows: const [
          Shadow(color: Color(0xCCFF3D00), blurRadius: 7, offset: Offset(0, 0)),
          Shadow(color: Color(0xFFFF9E80), blurRadius: 2, offset: Offset(0, 0)),
        ],
      ),
    );

    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
    final x = size.width - tp.width - (size.width * 0.05);
    final y = size.height - tp.height - (size.height * 0.04);
    tp.paint(canvas, Offset(x, y));
  }
}