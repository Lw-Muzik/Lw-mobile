import 'package:flutter/material.dart';
import 'package:sleek_circular_slider/sleek_circular_slider.dart';

class RoundSlider extends StatelessWidget {
  final String title;
  final double value;
  final double max;
  final double min;
  final double dB;
  final double width;
  final double height;
  final ValueChanged<double> onChanged;
  const RoundSlider({
    super.key,
    required this.title,
    required this.onChanged,
    required this.value,
    required this.max,
    required this.min,
    required this.dB,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: SleekCircularSlider(
          innerWidget: (percentage) => Stack(
                // mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Center(
                    child: Text("${percentage.toStringAsFixed(1)} dB",
                        style: Theme.of(context).textTheme.bodyLarge),
                  ),
                  Positioned(
                      bottom: -5,
                      right: 0,
                      left: 0,
                      child: Center(
                        child: Text(title,
                            style: Theme.of(context).textTheme.titleMedium),
                      )),
                ],
              ),
          initialValue: value,
          min: min,
          max: max,
          appearance: CircularSliderAppearance(
              customWidths: CustomSliderWidths(
                  progressBarWidth: 7,
                  handlerSize: 10,
                  trackWidth: 7,
                  shadowWidth: 0),
              customColors: CustomSliderColors(
                dotColor: Theme.of(context).primaryColor,
                trackColor: Theme.of(context).primaryColor.withOpacity(0.2),
                progressBarColor: Theme.of(context).primaryColor,
              )),
          onChange: onChanged),
    );
  }
}
