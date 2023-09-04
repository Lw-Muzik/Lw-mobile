import 'package:flutter/material.dart';

class LineVisualiser extends CustomPainter {
  final List<int> waveData;
  final double width;
  final double height;
  final Color color;

  LineVisualiser({
    required this.waveData,
    required this.width,
    required this.height,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    Path path = Path();

    double dx = width / waveData.length;

    for (int i = 0; i < waveData.length; i++) {
      double x = i * dx;
      double y = height - waveData[i] * height;
      // print("height $x");
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}
