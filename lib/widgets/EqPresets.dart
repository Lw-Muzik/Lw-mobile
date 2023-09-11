import 'package:eq_app/controllers/AppController.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Helpers/Channel.dart';

class EqPresets extends StatelessWidget {
  const EqPresets({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(builder: (context, controller, child) {
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: Stream.fromFuture(Channel.getPreset()),
        builder: (context, presetData) {
          return presetData.hasData
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(
                      presetData.data!.length,
                      (index) => Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: InkWell(
                          onTap: () {
                            context.read<AppController>().selectedPreset =
                                index;

                            Channel.setPreset(
                                presetData.data?[index]["preset"]);
                          },
                          child: Chip(
                            backgroundColor: controller.selectedPreset == index
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            label: Text(
                              presetData.data?[index]["preset"],
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.apply(
                                      color: controller.selectedPreset == index
                                          ? Colors.black
                                          : Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : Container();
        },
      );
    });
  }
}
