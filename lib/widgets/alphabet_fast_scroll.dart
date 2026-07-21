import 'package:flutter/material.dart';

/// A fixed-extent [ListView] with an A–Z rail for jumping through long lists —
/// the standard "scrub the alphabet" affordance every large music library has.
///
/// The rail only appears when a [sectionKeyOf] is supplied and the list is long
/// enough to warrant it; jumps are O(1) because a fixed [itemExtent] means an
/// item's offset is just `index * itemExtent`.
class AlphabetFastScroll extends StatefulWidget {
  const AlphabetFastScroll({
    super.key,
    required this.itemCount,
    required this.itemExtent,
    required this.itemBuilder,
    this.sectionKeyOf,
    this.padding,
    this.minItemsForRail = 30,
  });

  final int itemCount;
  final double itemExtent;
  final IndexedWidgetBuilder itemBuilder;

  /// First-letter of item [index]. Null disables the rail (e.g. when the list
  /// is sorted by date or duration, where an alphabet has no meaning).
  final String Function(int index)? sectionKeyOf;

  final EdgeInsets? padding;
  final int minItemsForRail;

  @override
  State<AlphabetFastScroll> createState() => _AlphabetFastScrollState();
}

class _AlphabetFastScrollState extends State<AlphabetFastScroll> {
  static const List<String> _alphabet = [
    '#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', //
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
  ];

  final ScrollController _scroll = ScrollController();
  Map<String, int> _letterIndex = const {};
  String? _activeLetter;

  bool get _railEnabled =>
      widget.sectionKeyOf != null && widget.itemCount >= widget.minItemsForRail;

  @override
  void initState() {
    super.initState();
    _rebuildIndex();
  }

  @override
  void didUpdateWidget(covariant AlphabetFastScroll old) {
    super.didUpdateWidget(old);
    if (old.itemCount != widget.itemCount ||
        old.sectionKeyOf != widget.sectionKeyOf) {
      _rebuildIndex();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _rebuildIndex() {
    final keyOf = widget.sectionKeyOf;
    if (keyOf == null) {
      _letterIndex = const {};
      return;
    }
    final map = <String, int>{};
    for (var i = 0; i < widget.itemCount; i++) {
      final k = _normalize(keyOf(i));
      map.putIfAbsent(k, () => i);
    }
    _letterIndex = map;
  }

  static String _normalize(String raw) {
    if (raw.isEmpty) return '#';
    final c = raw.trimLeft();
    if (c.isEmpty) return '#';
    final upper = c[0].toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(upper) ? upper : '#';
  }

  void _jumpToLetter(String letter) {
    int? idx = _letterIndex[letter];
    if (idx == null) {
      // Fall through to the next present letter so an absent one still lands
      // somewhere sensible.
      var passed = false;
      for (final l in _alphabet) {
        if (l == letter) passed = true;
        if (passed && _letterIndex.containsKey(l)) {
          idx = _letterIndex[l];
          break;
        }
      }
    }
    idx ??= 0;
    if (!_scroll.hasClients) return;
    final target =
        (idx * widget.itemExtent).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.jumpTo(target);
  }

  void _onRailDrag(Offset localPos, double railHeight) {
    final ratio = (localPos.dy / railHeight).clamp(0.0, 0.999);
    final letter = _alphabet[(ratio * _alphabet.length).floor()];
    if (letter != _activeLetter) {
      setState(() => _activeLetter = letter);
      _jumpToLetter(letter);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView.builder(
      controller: _scroll,
      padding: widget.padding,
      itemExtent: widget.itemExtent,
      itemCount: widget.itemCount,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: widget.itemBuilder,
    );

    if (!_railEnabled) return list;

    final theme = Theme.of(context);
    return Stack(
      children: [
        list,
        Positioned(
          top: 0,
          bottom: 0,
          right: 2,
          child: _buildRail(theme),
        ),
        if (_activeLetter != null)
          Center(
            child: IgnorePointer(
              child: Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Text(
                  _activeLetter!,
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRail(ThemeData theme) {
    final onSurface = theme.colorScheme.onSurface;
    return LayoutBuilder(
      builder: (context, constraints) {
        final railHeight = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (d) => _onRailDrag(d.localPosition, railHeight),
          onVerticalDragUpdate: (d) => _onRailDrag(d.localPosition, railHeight),
          onVerticalDragEnd: (_) => setState(() => _activeLetter = null),
          onTapDown: (d) => _onRailDrag(d.localPosition, railHeight),
          onTapUp: (_) => setState(() => _activeLetter = null),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final l in _alphabet)
                  Text(
                    l,
                    style: TextStyle(
                      fontSize: 9.5,
                      height: 1.0,
                      fontWeight: FontWeight.w600,
                      color: onSurface.withValues(alpha: 0.45),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
