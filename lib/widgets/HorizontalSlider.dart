import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class HorizontalSlider extends StatelessWidget {
  final String title;
  final double value;
  final double max;
  final double min;
  final String dB;
  final ValueChanged<double> onChanged;
  const HorizontalSlider(
      {super.key,
      required this.title,
      required this.onChanged,
      required this.value,
      required this.max,
      required this.min,
      required this.dB});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        SizedBox(
          width: MediaQuery.of(context).size.width / 1.4,
          child: SliderTheme(
            data: const SliderThemeData(
              trackHeight: 3,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider.adaptive(
              max: max,
              min: min,
              value: value,
              onChanged: onChanged,
            ),
          ),
        ),
        Text(
          dB,
          style: Theme.of(context).textTheme.bodyLarge,
        )
      ],
    );
  }
}
