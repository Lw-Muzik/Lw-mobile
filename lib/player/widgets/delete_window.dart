import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/controllers/library_controller.dart';
import '/helpers/channel.dart';
import '/Routes/routes.dart';

class DeleteWindow extends StatefulWidget {
  final String folder;
  final String type;
  const DeleteWindow({super.key, required this.folder, required this.type});

  @override
  State<DeleteWindow> createState() => _DeleteWindowState();
}

class _DeleteWindowState extends State<DeleteWindow> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18.0),
      child: SizedBox(
        height: 200,
        child: Column(
          // mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Center(
              child: Text(
                "Delete ${widget.type}",
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox.square(dimension: 40),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: "Are you sure you want to delete ",
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  TextSpan(
                    text: widget.folder.split('/').last.endsWith(".mp3")
                        ? widget.folder.split('/').last.replaceAll(".mp3", "")
                        : widget.folder.split('/').last,
                    style: Theme.of(context).textTheme.titleMedium!
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox.square(dimension: 9),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox.square(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    TextButton(
                      onPressed: () async {
                        // Captured before the await; the sheet is closed below
                        // and its context goes with it.
                        final messenger = ScaffoldMessenger.of(context);
                        final library = context.read<LibraryController>();
                        Routes.pop(context);
                        final ok = await Channel.deleteManager(widget.folder);
                        if (ok) await library.rescan();
                        messenger.showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                              ok
                                  ? 'Deleted ${widget.folder.split('/').last}'
                                  : 'Could not delete that folder',
                            ),
                          ),
                        );
                      },
                      child: const Text("Delete"),
                    ),
                    TextButton(
                      onPressed: () => Routes.pop(context),
                      child: const Text("Cancel"),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
