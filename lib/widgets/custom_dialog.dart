import 'package:flutter/material.dart';

class CustomDialog extends StatefulWidget {
  const CustomDialog({super.key});

  @override
  State<CustomDialog> createState() => _CustomDialogState();
}

class _CustomDialogState extends State<CustomDialog> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        height: MediaQuery.of(context).size.width / 2,
        child: RadioGroup<int>(
          groupValue: 1,
          onChanged: (x) {},
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RadioListTile<int>(
                value: 0,
                title: Text(
                  "Light Mode",
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              RadioListTile<int>(
                value: 1,
                title: const Text("Dark Mode"),
              ),
              RadioListTile<int>(
                value: 2,
                title: const Text("Follow Day / Night"),
              )
            ],
          ),
        ),
      ),
    );
  }
}
