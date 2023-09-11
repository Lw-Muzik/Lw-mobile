import 'package:eq_app/pages/Equalizer.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/AppController.dart';

class Header extends StatelessWidget {
  const Header({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(builder: (context, controller, child) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: <Widget>[
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              iconSize: 32,
              icon: const Icon(
                Icons.keyboard_arrow_down_outlined,
                color: Colors.white,
              ),
            ),
            Expanded(
              child: Column(
                children: <Widget>[
                  Text(
                    "${controller.songId + 1} of ${controller.songs.length} TRACKS",
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall!
                        .copyWith(fontWeight: FontWeight.w300)
                        .apply(color: Colors.white),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const Equalizer(),
                ),
              ),
              icon: const Icon(
                Icons.equalizer_rounded,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
    });
  }
}
