import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

/// A wrapper that adds continuous pinch-to-zoom to any grid/list layout.
///
/// During a two-finger pinch the [maxCrossAxisExtent] changes every frame,
/// causing the grid to reflow smoothly. On release the extent snaps to the
/// nearest clean column count with an easeOutCubic animation.
///
/// If [listBuilder] is provided, pinching out past [listModeExtent] crossfades
/// into list mode.
class PinchZoomGrid extends StatefulWidget {
  final double initialExtent;
  final double minExtent;
  final double maxExtent;
  final double listModeExtent;
  final ValueChanged<double>? onExtentChanged;
  final Widget Function(double extent) gridBuilder;
  final Widget? listBuilder;

  const PinchZoomGrid({
    super.key,
    required this.initialExtent,
    this.minExtent = 80.0,
    this.maxExtent = 300.0,
    this.listModeExtent = 260.0,
    this.onExtentChanged,
    required this.gridBuilder,
    this.listBuilder,
  });

  @override
  State<PinchZoomGrid> createState() => _PinchZoomGridState();
}

class _PinchZoomGridState extends State<PinchZoomGrid>
    with SingleTickerProviderStateMixin {
  final Map<int, Offset> _pointers = {};
  double? _initialDistance;
  double _baseExtent = 200.0;
  late double _currentExtent;
  bool _isPinching = false;

  late AnimationController _snapCtrl;
  Animation<double>? _snapAnim;
  VoidCallback? _snapListener;

  @override
  void initState() {
    super.initState();
    _currentExtent = widget.initialExtent;
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void didUpdateWidget(PinchZoomGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync with external changes when not actively zooming
    if (!_isPinching && !_snapCtrl.isAnimating) {
      _currentExtent = widget.initialExtent;
    }
  }

  @override
  void dispose() {
    _removeSnapListener();
    _snapCtrl.dispose();
    super.dispose();
  }

  void _removeSnapListener() {
    if (_snapListener != null) {
      _snapAnim?.removeListener(_snapListener!);
      _snapListener = null;
    }
  }

  // ---- Pointer tracking (raw Listener avoids scroll gesture conflicts) ----

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 2) {
      _snapCtrl.stop();
      _removeSnapListener();
      _initialDistance = _distance();
      _baseExtent = _currentExtent;
      _isPinching = true;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length != 2 || _initialDistance == null || !_isPinching) {
      return;
    }
    final ratio = _distance() / _initialDistance!;
    setState(() {
      _currentExtent =
          (_baseExtent * ratio).clamp(widget.minExtent, widget.maxExtent);
    });
  }

  void _onPointerUpOrCancel(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2 && _isPinching) {
      _isPinching = false;
      _initialDistance = null;
      _snapToNearestColumn();
    }
  }

  double _distance() {
    final pts = _pointers.values.toList();
    return (pts[0] - pts[1]).distance;
  }

  // ---- Snap animation ----

  void _snapToNearestColumn() {
    final screenWidth = MediaQuery.of(context).size.width - 24; // padding

    double snapExtent;
    if (widget.listBuilder != null && _currentExtent >= widget.listModeExtent) {
      // Snap into list mode
      snapExtent = widget.maxExtent;
    } else {
      final maxCols = (screenWidth / widget.minExtent).floor().clamp(2, 10);
      final cols = (screenWidth / _currentExtent).round().clamp(2, maxCols);
      final ceiling = widget.listBuilder != null
          ? widget.listModeExtent - 1
          : widget.maxExtent;
      snapExtent = (screenWidth / cols).clamp(widget.minExtent, ceiling);
    }

    final startExtent = _currentExtent;
    _removeSnapListener();

    _snapAnim = Tween<double>(begin: startExtent, end: snapExtent).animate(
      CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOutCubic),
    );
    _snapListener = () => setState(() => _currentExtent = _snapAnim!.value);
    _snapAnim!.addListener(_snapListener!);

    _snapCtrl.reset();
    _snapCtrl.forward().then((_) {
      _removeSnapListener();
      HapticFeedback.selectionClick();
      widget.onExtentChanged?.call(_currentExtent);
    });
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final hasListMode = widget.listBuilder != null;

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUpOrCancel,
      onPointerCancel: _onPointerUpOrCancel,
      child: hasListMode
          ? _buildWithTransition()
          : widget.gridBuilder(_currentExtent),
    );
  }

  Widget _buildWithTransition() {
    // Blend zone: 50px range leading up to the list mode threshold
    const blendRange = 50.0;
    final blendStart = widget.listModeExtent - blendRange;
    final t = ((_currentExtent - blendStart) / blendRange).clamp(0.0, 1.0);

    // Pure grid — no overhead
    if (t <= 0.0) {
      return widget.gridBuilder(_currentExtent);
    }
    // Pure list
    if (t >= 1.0) {
      return widget.listBuilder!;
    }

    // Smooth curve for more natural feel
    final curve = Curves.easeInOutCubic.transform(t);

    // 3D perspective transforms — grid tilts back, list comes forward
    final gridScale = 1.0 - curve * 0.08;
    final gridMatrix = Matrix4.identity()
      ..setEntry(3, 2, 0.0015) // perspective depth
      ..translateByVector3(Vector3(0.0, curve * 24, 0.0))
      ..rotateX(curve * 0.35)
      ..scaleByVector3(Vector3.all(gridScale));

    final listScale = 0.92 + curve * 0.08;
    final listMatrix = Matrix4.identity()
      ..setEntry(3, 2, 0.0015)
      ..translateByVector3(Vector3(0.0, (1.0 - curve) * -24, 0.0))
      ..rotateX((1.0 - curve) * -0.35)
      ..scaleByVector3(Vector3.all(listScale));

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Grid — tilts away
          if (curve < 0.95)
            Transform(
              transform: gridMatrix,
              alignment: Alignment.topCenter,
              child: Opacity(
                opacity: math.min(1.0, (1.0 - curve) * 1.5),
                child: widget.gridBuilder(
                  _currentExtent.clamp(widget.minExtent, widget.listModeExtent),
                ),
              ),
            ),
          // List — tilts in
          if (curve > 0.05)
            Transform(
              transform: listMatrix,
              alignment: Alignment.topCenter,
              child: Opacity(
                opacity: math.min(1.0, curve * 1.5),
                child: widget.listBuilder!,
              ),
            ),
        ],
      ),
    );
  }
}
