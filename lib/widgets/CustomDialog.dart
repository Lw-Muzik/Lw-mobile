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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RadioListTile(
              groupValue: 1,
              value: 0,
              onChanged: (x) {},
              title: Text(
                "Light Mode",
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            RadioListTile(
              groupValue: 1,
              value: 0,
              onChanged: (x) {},
              title: const Text("Dark Mode"),
            ),
            RadioListTile(
              groupValue: 1,
              value: 0,
              onChanged: (x) {},
              title: const Text("Follow Day / Night"),
            )
          ],
        ),
      ),
    );
  }
}
