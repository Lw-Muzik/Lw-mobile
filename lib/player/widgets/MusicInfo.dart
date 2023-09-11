import 'package:flutter/material.dart';

import '../../controllers/AppController.dart';

class MusicInfo extends StatefulWidget {
  final AppController controller;
  const MusicInfo({super.key, required this.controller});

  @override
  State<MusicInfo> createState() => _MusicInfoState();
}

class _MusicInfoState extends State<MusicInfo>
    with SingleTickerProviderStateMixin {
  AnimationController? _titleController;
  Animation<double>? _titleAnimation;
  final ScrollController _titleScrollController = ScrollController();
  final ScrollController _artistScrollController = ScrollController();
  @override
  void initState() {
    super.initState();
    _titleController = AnimationController(
      vsync: this,
      value: 0,
      duration: const Duration(milliseconds: 6200),
      reverseDuration: const Duration(milliseconds: 5200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _titleController?.dispose();
    _titleScrollController.dispose();
    _artistScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _titleAnimation = Tween<double>(
      begin: -10,
      end: widget.controller.songs[widget.controller.songId].title.length >
                  70 ||
              widget.controller.songs[widget.controller.songId].artist!.length >
                  70
          ? 400
          : 220,
    ).animate(_titleController!);
    // if (widget.controller.songs[widget.controller.songId].title.length < 32 ||
    //     widget.controller.songs[widget.controller.songId].artist!.length < 32) {
    //   _titleController?.stop();
    // } else {
    //   _titleController?.repeat(reverse: true);
    // }
    return // Music info
        Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 30),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                //-_titleAnimation!.value
                AnimatedBuilder(
                  builder: (context, child) {
                    if (_titleScrollController.hasClients) {
                      _titleScrollController.jumpTo(widget
                                  .controller
                                  .songs[widget.controller.songId]
                                  .title
                                  .length >
                              32
                          ? _titleAnimation!.value
                          : 0);
                      (widget.controller.songs[widget.controller.songId].title
                          .length);
                      _artistScrollController.jumpTo(widget
                                  .controller
                                  .songs[widget.controller.songId]
                                  .artist!
                                  .length >
                              32
                          ? _titleAnimation!.value
                          : 0);
                    }

                    return SingleChildScrollView(
                      controller: _titleScrollController,
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        widget.controller.songs[widget.controller.songId].title
                            .toString(),
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        style: Theme.of(context).textTheme.headlineSmall!.apply(
                              color: Colors.white,
                            ),
                      ),
                    );
                  },
                  animation: _titleAnimation!,
                ),
                const SizedBox(height: 5),
                AnimatedBuilder(
                    animation: _titleAnimation!,
                    builder: (context, child) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: _artistScrollController,
                        child: Text(
                          widget.controller.songs[widget.controller.songId]
                                  .artist ??
                              "Unknown artist",
                          maxLines: 1,
                          overflow: TextOverflow.visible,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium!
                              .apply(color: Colors.white.withOpacity(0.5)),
                        ),
                      );
                    }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
