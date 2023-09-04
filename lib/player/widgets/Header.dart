import 'package:eq_app/pages/Equalizer.dart';
import 'package:flutter/material.dart';

class Header extends StatelessWidget {
  const Header({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            iconSize: 32,
            icon: const Icon(
              Icons.arrow_drop_down,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: Column(
              children: <Widget>[
                Text(
                  "PLAYING NOW",
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyText1!
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
  }
}
