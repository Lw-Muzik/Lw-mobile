import 'package:eq_app/controllers/AppController.dart';
import 'package:eq_app/models/eq_models.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class EqPresets extends StatefulWidget {
  const EqPresets({super.key});

  @override
  State<EqPresets> createState() => _EqPresetsState();
}

class _EqPresetsState extends State<EqPresets> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, _) {
        final builtInNames = BuiltInPresets.names;
        final userPresets = controller.savedPresets.keys
            .where((k) => !k.startsWith('_device_'))
            .toList();
        final allNames = [...builtInNames, ...userPresets];

        return SizedBox(
          height: 42,
          child: ListView.separated(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            itemCount: allNames.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final name = allNames[index];
              final isSelected = controller.activePresetName == name;
              final isUser = index >= builtInNames.length;

              return ChoiceChip(
                label: Text(name),
                selected: isSelected,
                onSelected: (_) {
                  if (isUser) {
                    controller.loadPreset(name);
                  } else {
                    controller.applyBuiltInPreset(name);
                  }
                },
                avatar: isUser ? const Icon(Icons.person, size: 16) : null,
                selectedColor: Theme.of(context).colorScheme.primary,
                labelStyle: TextStyle(
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                ),
              );
            },
          ),
        );
      },
    );
  }
}
