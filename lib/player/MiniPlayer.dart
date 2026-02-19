import 'package:flutter/material.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key, required this.onTap});
  final Function onTap;
  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  @override
  Widget build(BuildContext context) {
    final colorTheme = Theme.of(context).colorScheme;
    return Container(
      color: colorTheme.onSurface,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 71.0,
        child: Column(
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => widget.onTap(),
                  child: SizedBox(
                    width: 70,
                    height: 70,
                    child: Image.asset("assets/audio.jpeg", fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Wurkit (Original Mix)',
                          style: TextStyle(color: colorTheme.onPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(width: 8, height: 8),
                      Text('Kyle Watson',
                          style: TextStyle(
                              color: colorTheme.onPrimary.withOpacity(0.5),
                              fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Icon(Icons.favorite_border, color: colorTheme.onPrimary),
                const SizedBox(width: 20),
                GestureDetector(
                  onTap: () {},
                  child: Icon(Icons.play_arrow,
                      color: colorTheme.onPrimary, size: 30),
                ),
                const SizedBox(width: 20),
              ],
            ),
            Divider(color: colorTheme.surface, height: 1),
          ],
        ),
      ),
    );
  }
}
