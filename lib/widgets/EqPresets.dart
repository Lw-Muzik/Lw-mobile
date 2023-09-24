import 'package:eq_app/controllers/AppController.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Helpers/Channel.dart';

class EqPresets extends StatefulWidget {
  const EqPresets({super.key});

  @override
  State<EqPresets> createState() => _EqPresetsState();
}

class _EqPresetsState extends State<EqPresets> {
  @override
  void initState() {
    super.initState();
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        (context.read<AppController>().selectedPreset * 80).toDouble(),
        duration: const Duration(milliseconds: 900),
        curve: Curves.decelerate,
      );
    }
  }

  final ScrollController _scrollController = ScrollController();
  @override
  Widget build(BuildContext context) {
    // var controller = Provider.of<AppController>(context);
    return Consumer<AppController>(builder: (context, controller, ch) {
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: Channel.getPreset(),
        builder: (context, presetData) {
          return presetData.hasData
              ? SingleChildScrollView(
                  controller: _scrollController,
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
                              presetData.data?[index]["preset"],
                            );
                            if (_scrollController.hasClients) {
                              _scrollController.animateTo(
                                (index * 80).toDouble(),
                                duration: const Duration(milliseconds: 900),
                                curve: Curves.decelerate,
                              );
                            }
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
                                        : Colors.white,
                                  ),
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
