import 'package:flutter/material.dart';
import 'dart:math' as math;

class CircularKnob extends StatefulWidget {
  const CircularKnob({super.key});

  @override
  State<CircularKnob> createState() => _CircularKnobState();
}

class _CircularKnobState extends State<CircularKnob>
    with SingleTickerProviderStateMixin {
  double knobValue = 0.5; // Initialize with your default value
  double targetKnobValue = 0.5; // Initialize the target knob value
  bool isDragging = false;
  double knobPointerX = 0.0; // Initialize the pointer X position

  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 200), // Adjust the animation duration
    );

    _animation = Tween<double>(
      begin: knobValue,
      end: targetKnobValue,
    ).animate(_controller)
      ..addListener(() {
        setState(() {
          knobValue = _animation.value;
        });
      });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) {
        setState(() {
          isDragging = true;
        });
      },
      onPanUpdate: (details) {
        // Calculate the angle between the center and touch point
        final RenderBox renderBox = context.findRenderObject() as RenderBox;
        final double centerX = renderBox.size.width / 2;
        final double centerY = renderBox.size.height / 2;
        final double touchX = details.localPosition.dx;
        final double touchY = details.localPosition.dy;
        final double angle = math.atan2(touchY - centerY, touchX - centerX);

        // Normalize the angle to a value between 0 and 1
        final double normalizedAngle = (angle + math.pi) / (2 * math.pi);

        // Update the target knobValue
        targetKnobValue = normalizedAngle;

        // Update the pointer's X position
        knobPointerX = touchX;

        // Start the animation
        _controller.reset();
        _controller.forward();
      },
      onPanEnd: (details) {
        setState(() {
          isDragging = false;
        });
      },
      child: CustomPaint(
        size: Size(100, 100), // Adjust size as needed
        painter: CircularKnobPainter(
            knobValue: knobValue,
            isDragging: isDragging,
            pointerX: knobPointerX),
      ),
    );
  }
}

class CircularKnobPainter extends CustomPainter {
  final double knobValue;
  final bool isDragging;
  final double pointerX;
  final Color knobColor;
  final double pointerRadius;
  CircularKnobPainter(
      {this.knobColor = Colors.blueGrey,
      this.pointerRadius = 10.0,
      required this.knobValue,
      required this.pointerX,
      required this.isDragging});
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    // Customize the knob color

    // Draw the circular knob
    final knobPaint = Paint()
      ..color = knobColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, knobPaint);

    // Draw the pointer if it's being dragged
    // if (isDragging) {
    final pointerRadius = radius + 10.0; // Adjust pointer size
    final pointerColor = Colors.blue; // Customize the pointer color

    // Calculate the pointer's position based on knobValue
    final angle = 2 * math.pi * knobValue - math.pi / 2;
    // final pointerX = center.dx + pointerRadius * math.cos(angle);
    final pointerY = center.dy + pointerRadius * math.sin(angle);
    final pointerCenter = Offset(pointerX, pointerY);

    // Draw the glowing pointer
    final pointerPaint = Paint()..color = pointerColor;
    // ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0);
    canvas.drawCircle(pointerCenter, pointerRadius, pointerPaint);
    // }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}
