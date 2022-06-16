import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class ListMusic {
  Widget top;
  Widget bot;
  Axis scroll;
  DragStartBehavior dragStartBehavior = DragStartBehavior.start;
  Clip clipBehavior = Clip.hardEdge;
  ScrollController controller;
  ListMusic(
      {this.top,
      this.dragStartBehavior,
      this.clipBehavior,
      this.bot,
      this.scroll,
      this.controller});
}
