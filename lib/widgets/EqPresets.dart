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
  final ScrollController _scrollController = ScrollController();
  @override
  Widget build(BuildContext context) {
    var controller = Provider.of<AppController>(context);
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Stream.fromFuture(Channel.getPreset()),
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
                          context.read<AppController>().selectedPreset = index;
                          Channel.setPreset(
                            presetData.data?[index]["preset"],
                          );
                          if (_scrollController.hasClients) {
                            _scrollController.animateTo((index * 80).toDouble(),
                                duration: const Duration(milliseconds: 900),
                                curve: Curves.decelerate);
                          }
                        },
                        child: Chip(
                          backgroundColor: controller.selectedPreset == index
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          label: Text(
                            presetData.data?[index]["preset"],
                            style:
                                Theme.of(context).textTheme.labelLarge?.apply(
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
  }
}
