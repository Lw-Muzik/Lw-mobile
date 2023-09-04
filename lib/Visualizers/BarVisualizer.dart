import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class BarVisualizer extends CustomPainter {
  final List<int> waveData;
  final double height;
  final double width;
  final Color color;
  final Paint wavePaint;
  final int density;
  final int gap;

  BarVisualizer(
      {required this.waveData,
      required this.height,
      required this.width,
      required this.color,
      this.density = 50,
      this.gap = 2})
      : wavePaint = Paint()
          ..color = color.withOpacity(1.0)
          ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    double barWidth = width / density;
    double div = waveData.length / density;
    wavePaint.strokeWidth = barWidth - gap;
    for (int i = 0; i < density; i++) {
      int bytePosition = (i * div).ceil();
      double top = (height / 2 - (((waveData[bytePosition]) - 128).abs()));
      double barX = (i * barWidth) + (barWidth / 2);
      if (top > height) {
        top = top - height;
      }
      canvas.drawLine(Offset(barX, height / 2), Offset(barX, top), wavePaint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}
