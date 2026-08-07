/// Searching YouTube's catalog.
///
/// Six filters, each its own request — that is how YT Music's own search works,
/// and the unfiltered query answers with a different, shallower set (a top
/// result and a handful of each kind) rather than with everything.
///
/// # The two rules that keep typing cheap
///
/// * **Suggestions are debounced and superseded.** One request per pause, not
///   one per keystroke, and a reply that arrives after the query has moved on is
///   dropped rather than rendered — otherwise a slow network shows the user
///   completions for a word they have already finished typing.
/// * **A failed suggestion request is silent.** It costs the completions and
///   nothing else; replacing what someone is typing with an error message is a
///   worse outcome than showing them nothing.
///
/// # Playing a result starts a station
///
/// Unlike a playlist or an album, a page of search results is not a running
/// order — it is twenty answers to one question, and following the song someone
/// picked with its own remixes, covers and live versions is not listening to
/// music. So a tapped result plays alone and seeds an endless station, which is
/// what desktop does and what YT Music itself does. Autoplay off falls back to
/// queueing the results, since that fetches nothing.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/ytmusic/yt_models.dart';
import '../../services/ytmusic/yt_repository.dart';
import 'widgets/yt_widgets.dart';
import 'yt_open.dart';

class YtSearchPage extends StatefulWidget {
  const YtSearchPage({super.key});

  @override
  State<YtSearchPage> createState() => _YtSearchPageState();
}

class _YtSearchPageState extends State<YtSearchPage> {
  static const _debounce = Duration(milliseconds: 250);

  final _controller = TextEditingController();
  final _focus = FocusNode();

  Timer? _timer;
  List<String> _suggestions = const [];
  List<ExploreShelf> _shelves = const [];
  SearchFilter _filter = SearchFilter.top;
  String _query = '';
  bool _loading = false;
  String? _error;

  /// Monotonic ticket for the newest request. A reply whose ticket isn't the
  /// current one belongs to a query the user has moved past.
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _suggestions = const [];
        _shelves = const [];
        _query = '';
        _error = null;
      });
      return;
    }
    _timer = Timer(_debounce, () => _suggest(value));
  }

  Future<void> _suggest(String value) async {
    final ticket = ++_ticket;
    final suggestions =
        await YtMusicRepository.instance.suggestions(value.trim());
    if (!mounted || ticket != _ticket) return;
    setState(() => _suggestions = suggestions);
  }

  Future<void> _search(String value, {SearchFilter? filter}) async {
    final query = value.trim();
    if (query.isEmpty) return;
    _timer?.cancel();
    _focus.unfocus();
    if (_controller.text != query) _controller.text = query;

    final ticket = ++_ticket;
    setState(() {
      _query = query;
      _filter = filter ?? _filter;
      _loading = true;
      _error = null;
      _suggestions = const [];
    });

    try {
      final shelves =
          await YtMusicRepository.instance.search(query, _filter);
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _shelves = shelves;
        _loading = false;
      });
      YtMusicRepository.instance.prefetchAudio([
        for (final shelf in shelves)
          for (final item in shelf.items)
            if (item.isPlayable) item.id,
      ]);
    } catch (e) {
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _loading = false;
        _shelves = const [];
        _error = e is YtException ? e.message : 'Search failed.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: 'Songs, artists, albums…',
            border: InputBorder.none,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () {
                      _controller.clear();
                      _onChanged('');
                      _focus.requestFocus();
                    },
                  ),
          ),
          onChanged: (value) {
            // Rebuild so the clear button tracks the field's emptiness.
            setState(() {});
            _onChanged(value);
          },
          onSubmitted: _search,
        ),
      ),
      body: Column(
        children: [
          if (_query.isNotEmpty)
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: SearchFilter.values.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final filter = SearchFilter.values[index];
                  return Center(
                    child: ChoiceChip(
                      label: Text(filter.label),
                      selected: filter == _filter,
                      onSelected: (_) => _search(_query, filter: filter),
                    ),
                  );
                },
              ),
            ),
          Expanded(child: _body(theme)),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_suggestions.isNotEmpty) {
      return ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: _suggestions.length,
        itemBuilder: (context, index) => ListTile(
          dense: true,
          leading: Icon(
            Icons.search_rounded,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          title: Text(_suggestions[index]),
          onTap: () => _search(_suggestions[index]),
        ),
      );
    }

    if (_loading) return const YtSkeleton(shelves: 2);

    if (_error case final String message) {
      return YtMessage(
        icon: Icons.error_outline_rounded,
        title: "That search didn't run",
        body: message,
        onRetry: () => _search(_query),
      );
    }

    if (_query.isEmpty) {
      return const YtMessage(
        icon: Icons.search_rounded,
        title: 'Search YouTube Music',
        body: 'Songs, videos, albums, artists and playlists.',
      );
    }

    if (_shelves.isEmpty) {
      return YtMessage(
        icon: Icons.inbox_rounded,
        title: 'No ${_filter.label.toLowerCase()} for "$_query"',
        body: 'Try another filter, or a different spelling.',
      );
    }

    // Rows read better than cards for search results, where the question is
    // "which of these is the one I meant" — and a row states the artist, album
    // and duration a card has no room for. Shelves of pages (artists, albums)
    // stay as cards, which is what they are.
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
      itemCount: _shelves.length,
      itemBuilder: (context, index) {
        final shelf = _shelves[index];
        final rowsOnly = shelf.items.every((i) => i.isPlayable);
        if (!rowsOnly) {
          return YtShelfRow(
            shelf: shelf,
            onOpen: (item) => openExploreItem(
              context,
              item,
              siblings: shelf.items,
              radio: true,
            ),
            onHold: (item) => showTrackActions(context, item.asTrack()),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
              child: Text(
                shelf.title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (var i = 0; i < shelf.items.length; i++)
              YtTrackRow(
                track: shelf.items[i].asTrack(),
                onTap: () => openExploreItem(
                  context,
                  shelf.items[i],
                  siblings: shelf.items,
                  radio: true,
                ),
                onMore: () =>
                    showTrackActions(context, shelf.items[i].asTrack()),
              ),
          ],
        );
      },
    );
  }
}
