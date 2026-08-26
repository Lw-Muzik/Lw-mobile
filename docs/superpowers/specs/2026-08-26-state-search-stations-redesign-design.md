# Hype Muzik — playback state, unified search, stations, daily mixes, UI restructure

**Date:** 2026-08-26
**Branch:** `v1.0.0`
**Status:** design approved in chat; awaiting spec review

---

## 1. Summary

Seven phases, in dependency order:

| # | Phase | Depends on |
|---|-------|------------|
| 1 | Playback state and resume | — |
| 2 | Stations for every source | — |
| 3 | Unified search + radio hand-off | 2 |
| 4 | Listening signals and the daily mix engine | — |
| 5 | Navigation restructure and the Home surface | 4 |
| 6 | Library redesign | 5 |
| 7 | Settings redesign | — |

The player UI (`lib/player/**`) is **out of scope** by explicit instruction. It is
read from and routed to, never restyled.

Each phase gets its own implementation plan and its own verification pass. This
document is the program-level design they are cut from, not a substitute for them.

**One deliberate piece of rework:** Phase 1 fixes the bottom player's gate at all
eight call sites, and Phase 5 then collapses those eight scaffolds into a single
shell. That is accepted rather than avoided — Phase 1 is the defect the user hits
daily and it must not wait on a navigation rewrite. The Phase 1 change is one
identifier per site, so the throwaway cost is minutes.

---

## 2. Current state

Everything in this section was read from the tree at `2319b4c`, not recalled.

### 2.1 Playback session persistence already exists and works

`lib/services/playback_session.dart` serialises queue, shuffled order, index,
position and loop mode to
`getApplicationSupportDirectory()/playback_session.json`, windowed to 500 tracks.
`AppController._restoreSession` reads it back **without loading the player**, holding
the position in `_pendingResume`; `HypeAudioHandler.onBeforePlay`
(`lib/helpers/audio_handler.dart:233`) loads it on the first press of play.

That design is correct and is kept. The defects are all in the layers above it.

### 2.2 The bottom player is unreachable whenever it matters

`BottomPlayer` has **eight** call sites, and every one gates on *audio is currently
coming out of the speaker*:

| File | Line | Gate |
|---|---|---|
| `lib/pages/home.dart` | 260 | `controller.handler.player.playing` |
| `lib/pages/folder_songs.dart` | 130 | `isPlaying` |
| `lib/pages/artist_songs.dart` | 173 | `service.data ?? false` |
| `lib/pages/genre_songs.dart` | 141 | `service.data ?? false` |
| `lib/pages/playlist_songs.dart` | 145 | `service.data ?? false` |
| `lib/pages/album_songs.dart` | 145 | `service.data ?? false` |
| `lib/pages/settings.dart` | 110 | `!isEqMode && (service.data ?? false)` |
| `lib/pages/cloud/cloud_folder_songs.dart` | 365 | `isPlaying` |

Consequences: pausing removes the only visible transport; a restored session shows
nothing at all, so the resume path can never be triggered from the UI.

`home.dart:260` additionally reads `player.playing` **non-reactively** inside a
`Consumer<AppController>`, so it only re-evaluates when `AppController` happens to
notify.

### 2.3 The bottom player's transport bypasses the resume hook

`lib/widgets/globals.dart:77-78` calls `controller.handler.player.pause()` /
`controller.handler.player.play()` — the raw `just_audio` player.

`handler.play()` — where `onBeforePlay` lives — is called from **nowhere in `lib/`**.
`lib/player/widgets/controls.dart:101-102` is the only correct transport in the app,
and it routes through `controller.handler.pause` / `controller.handler.play`.

The five remaining `handler.player.play()` calls are internal load-then-autoplay
sites and are **correct as they are**:
`app_controller.dart:1310`, `:2436`, `:2473`, `lib/global/index.dart:475`, `:568`.

### 2.4 Video resume has a hole wider than the missing flag

`VideoRegistry` (`lib/services/video/video_registry.dart`) holds `_sources` and
`_videoMode` **in memory only**. Neither is persisted.

`VideoRegistry.sweepManifests()` deletes every `.mpd` at startup, by design, because
a manifest from a previous launch has no queue entry pointing at it.

`AppController._refreshTarget` returns early when `song.hasFreshTarget`, and
`hasFreshTarget` (`lib/models/track_extras.dart`) consults only `hype_expires_at`. So
a video killed two minutes after resolving comes back with a valid deadline and **no
manifest on disk**: the re-resolve is skipped and the player is handed a path to a
file that no longer exists.

### 2.5 Search covers neither YouTube nor a tappable cloud

`lib/pages/search_page.dart` (1,000+ lines) searches local songs, artists, albums,
folders, playlists and cloud files. It contains **no YouTube path**; YT search lives
in a separate screen, `lib/pages/discover/yt_search_page.dart`.

The Cloud section's `ListTile` (around line 836) has **no `onTap`** — cloud results
are decorative.

### 2.6 Radio is YouTube-only

`YtRadioQueue` (`lib/services/ytmusic/yt_playback.dart:473`) is built on InnerTube's
`next` endpoint and its continuation tokens. `AppController.playSongFromList`
(`:1169`) explicitly calls `YtRadioQueue.instance.detach()` for anything that is not
a YouTube stream.

Auto-radio on tap already exists for YouTube search only
(`yt_search_page.dart:260`, `:283` pass `radio: true`).

### 2.7 The library DB records too little to personalise anything

`lib/data/library_database.dart`, table `Songs`, has `playCount` and `lastPlayedSec`.
It has **no skip signal, no completion signal, no time-of-day, and no release year**
(only `dateAdded` / `dateModified`).

`schemaVersion` is **1** and `MigrationStrategy` declares **`onCreate` only — there is
no `onUpgrade`**.

### 2.8 Home is eight tabs and no landing surface

Android tabs: Folders, Playlists, Artists, Albums, Genres, Songs, Discover, Cloud.
iOS drops Folders and Playlists and leads with Discover. Playlists are tab 2 of 8.

Playlists come from `OnAudioQuery().queryPlaylists()`, which
`lib/pages/play_list_view.dart:27` documents as **not supported on iOS**. iOS
therefore has no playlists at all.

### 2.9 Settings is one 1,570-line scroll

Fifteen `_buildSectionHeader` sections in a single list: App Mode, Playback, Audio
Enhancement, Global Equalizer, Equalizer, Tone Controls, Appearance, Visualizer,
Visual Style, MilkDrop, Streaming, Cloud Storage, Stream to Desktop, Library,
About & Support.

### 2.10 Thermal constraint on any new chrome

`hype_thermal_fix` records that `BackdropFilter` re-reads its backdrop, cannot be
raster-cached, and recomputes **every frame the app produces**; it was the cause of
the app's heat problem and was replaced with `ImageFiltered` wherever the content
behind was static.

A translucent nav bar or mini player docked over a scrolling list is the pathological
case: genuinely dynamic content behind, recomputed for the entire duration of every
scroll. **The new chrome is opaque.**

### 2.11 Packages not currently present

No `palette_generator`, no `google_fonts`, no shimmer package.

---

## 3. Decisions

Each of these was chosen deliberately; the rationale is recorded so it is not
re-litigated later.

**D1 — Local and cloud stations score on metadata, offline.** There is no
"related tracks" service for a file on disk. A station scores every candidate against
the seed on artist, genre, album, `dateAdded` proximity and normalised play count,
then draws weighted-random. Works with no network and no account. Rejected: matching
YouTube's radio names against the local library (needs network, fails on small
libraries).

**D2 — Scoring uses `dateAdded`, not release year.** There is no year column. For a
personal library "music I added around the same time" is available and is arguably a
stronger signal than release date anyway.

**D3 — Unified search paints local and cloud instantly and streams YouTube in.**
One scrolling list of sections. The YouTube section shows a skeleton and fills when
the debounced request lands, and **fails silently** — being offline must never break
local search.

**D4 — Auto-radio fires from search results only.** Albums, playlists, folders,
artist and genre pages keep queueing their list, because those *are* a running order.
"Start radio" remains available explicitly, for every source, in the song options
sheet.

**D5 — `YtRadioQueue` is split rather than duplicated.** Queue management (station
identity, per-station single-flight, dedup, headroom, autoplay gate) moves to a
source-agnostic `RadioQueue`; batch production moves to a `StationSource`
implementation per source. The continuation token then lives *inside the source
object*, so a new station is a new object and structurally cannot inherit the
previous station's token — the bug recorded in `hype_radio_station_identity`. The
alternative (a second parallel singleton) duplicates top-up wiring across three
advance paths, which is the shape that caused `hype_radio_endless_reseed`.

**D6 — A `PlayEvents` table, not more denormalised columns.** One row per track
change carrying `songId`, `atSec`, `msPlayed`, `completed`. Play counts, skip rates
and hour-of-day histograms all derive from it. Pruned to 90 days.

**D7 — Daily mixes are deterministic per day and per daypart.** The RNG is seeded
with `yyyy-mm-dd` plus the daypart plus the mix index, so a mix is stable while the
user is looking at it and genuinely different tomorrow. This is the mechanism that
answers "the same old boring mixes"; it is not decoration.

**D8 — Playlists become app-owned, in drift.** MediaStore playlists are Android-only
and can only hold MediaStore ids, so they cannot hold a cloud track, a YouTube track,
or a saved mix. New `Playlists` / `PlaylistEntries` tables become the primary store;
on Android, MediaStore playlists are imported once at first run and remain readable.
This is what makes the Home playlist shelf exist on iOS at all.

**D9 — New chrome is opaque.** See §2.10. Glass stays only where it already is:
small regions over static artwork, via `ImageFiltered`.

**D10 — The player UI is not touched.** Out of scope by instruction.

---

## 4. Phase 1 — Playback state and resume

**Goal:** a paused track can always be resumed, from any surface, whether it is local
audio, cloud audio, a YouTube stream or a YouTube music video, and whether the pause
happened a second ago or across an app restart.

### 4.1 The bar becomes "now playing", not "now sounding"

Add to `AppController`:

```dart
/// Whether there is a track to show, regardless of whether it is sounding.
///
/// The bar is a handle on the current track, not an indicator that audio is
/// coming out. Gating it on `playing` removed the only transport the moment it
/// was needed — after a pause, and on a session restored from disk, which
/// starts paused by design.
bool get hasNowPlaying =>
    _songs.isNotEmpty && _songId >= 0 && _songId < _songs.length;
```

Replace the gate at all eight call sites in §2.2 with `controller.hasNowPlaying`.

`bottomPlayer()` in `lib/widgets/globals.dart` and `BottomPlayer.build` in
`lib/widgets/bottom_player.dart` both index `controller.songs[controller.songId]`
unguarded; both take the same bounds check.

### 4.2 Transport routes through the handler

`lib/widgets/globals.dart:77-78` becomes `controller.handler.pause()` /
`controller.handler.play()`.

Record the rule in a comment at the handler:

> User-facing transport calls `handler.play()`. Internal load-then-autoplay calls
> `player.play()` directly — those five sites run *after* the restore has already
> been consumed, and routing them through the handler would re-enter `onBeforePlay`.

### 4.3 Video restage

1. `PlaybackSession` gains `videoMode` (bool). Written on save, restored in
   `_restoreSession` **before** `_resumePendingSession` runs, so a station that tops
   up during resume keeps showing pictures.
2. `_refreshTarget` stops trusting `hasFreshTarget` alone for a video. A video track
   is stale unless it *also* has a live `VideoRegistry` entry:

   ```dart
   final needsRestage = song.isYtVideo && !VideoRegistry.instance.isVideo(song.id);
   if (videoId == null || (song.hasFreshTarget && !needsRestage)) return;
   ```

   Manifests are swept at every launch, so a fresh deadline says nothing about
   whether the file still exists.

### 4.4 Save on pause

`_startSessionTicker` writes only while playing. Add a save on pause so a pause
followed by a swipe-kill does not lose up to ten seconds. The store already
debounces, so this costs one write.

### 4.5 Known limitation, deliberately not fixed

`_transformEvent` and `playingStream` both read `_activePlayer`, which is the
*outgoing* player during a crossfade. The play/pause **icon** may therefore be
briefly stale mid-fade. This is pre-existing, cosmetic, affects the full player
equally, and fixing it means a swap-aware stream on the handler. Out of scope; the
bar's *visibility* no longer depends on it, which is the part that mattered.

### 4.6 Tests

- `hasNowPlaying` across empty queue, valid index, out-of-range index.
- A restored session plus one `handler.play()` loads the player at the saved
  position (the regression test for §4.2).
- `_refreshTarget` re-adopts a video whose deadline is fresh but whose registry entry
  is gone (the regression test for §4.3).
- `videoMode` survives a session round trip.

---

## 5. Phase 2 — Stations for every source

New directory `lib/services/radio/`.

| File | Owns |
|---|---|
| `station_source.dart` | `abstract class StationSource` — `fetch({exclude, limit})`, `advanceSeed()`, `seedKey` |
| `radio_queue.dart` | `RadioQueue`: station identity, per-station single-flight, `_offered` dedup, headroom, autoplay gate, append |
| `youtube_station.dart` | InnerTube `next`, continuation, reseed to `_offered.last` |
| `library_station.dart` | The offline scorer over the drift DB |
| `cloud_station.dart` | The same scorer over cached `CloudFile` lists |
| `track_similarity.dart` | The pure scoring function — no DB, no network |

`RadioQueue` is `YtRadioQueue`'s queue-management half **lifted verbatim**, including
`int _station`, `int? _fetchingFor` and `_acceptPage`. Its eight existing tests
(`test/ytmusic/yt_radio_station_test.dart`) move with it and must stay green; they are
the contract.

### 5.1 The scorer

```
score(candidate) =
    4.0  same artist
  + 2.5  same genre
  + 1.5  same album
  + 1.0  dateAdded within 30 days of the seed's
  + 0.5  normalised playCount
  + 0.5  low skip rate            (Phase 4 onward; 0 before that)
  - 3.0  already offered by this station
```

Weighted-random draw, batch of 25, top-up at five from the end. Cloud has no genre
column, so its scorer runs on artist, album and title only; the weights are shared,
the available terms differ.

`track_similarity.dart` takes plain values, not a database, so it is fully unit
testable with no fixtures.

### 5.2 Hand-off

One new method:

```dart
/// Plays [seed] alone and builds a station behind it.
Future<void> playStation(SongModel seed, StationSource source);
```

Sets a single-track queue, attaches the source to `RadioQueue`, calls
`fill(force: true)`. `playSongFromList`'s unconditional `detach()` stays as the
default; `playStation` is the deliberate other door.

### 5.3 Call-site migration

Six `YtRadioQueue` references (`app_controller.dart:960`, `:1033`, `:1169`, `:2328`,
`settings.dart:45`/`:256`/`:262`, `discover_view.dart:46`) move to `RadioQueue`. The
`YtRadioQueue` name is deleted rather than kept as a façade — two names for one thing
is how the original station-identity bug hid.

### 5.4 Tests

- The scorer: same artist beats same genre beats same album beats unrelated; an
  already-offered track is never drawn; a library of one returns nothing rather than
  looping the seed.
- The eight lifted station-identity tests, unchanged in meaning.
- Live YT tests re-run with `--tags live --run-skipped` (note: `-P live` does not
  work; `dart_test.yaml` marks the tag `skip:`, and "All tests skipped" reads as green
  at a glance).

---

## 6. Phase 3 — Unified search

### 6.1 Extraction

`search_page.dart` already mixes querying with rendering at 1,000+ lines, and this
phase adds a fourth source plus three tap paths. Querying moves to a
`UnifiedSearch` `ChangeNotifier` under `lib/pages/search/`; the page becomes the view.

### 6.2 YouTube section

Debounced 250 ms with a monotonic ticket, so a superseded reply is dropped rather
than rendered — the pattern already proven in `yt_search_page`. Skeleton while in
flight. **Silent on failure.** A "See all on YouTube" footer pushes to the existing
filtered screen, which is not changed.

### 6.3 Cloud rows become tappable

They currently are not. Tap plays the file and starts a cloud station.

### 6.4 Taps start stations

All three sections call `playStation` with the source for their kind. Everywhere
else in the app is untouched.

---

## 7. Phase 4 — Listening signals and the daily mix engine

### 7.1 Schema change — the migration is the risky part

`schemaVersion` 1 → 2, and `MigrationStrategy` gains an `onUpgrade`. There is no
`onUpgrade` today, so **shipping a schema change without writing one breaks the
library database for every existing install.** This is its own task with its own
test, not a footnote to the feature.

New tables:

```
PlayEvents(id, songId, atSec, msPlayed, completed)
Playlists(id, name, createdSec, updatedSec, coverPath)
PlaylistEntries(playlistId, position, songId, source, externalId)
```

`PlayEvents` is written once per track change and pruned to 90 days. `source` on a
playlist entry is what lets a playlist hold a cloud or YouTube track — see D8.

Derived views: play count, skip rate (`msPlayed / duration < 0.3`), and an
hour-of-day histogram per track and per genre.

### 7.2 Mix generation

1. **Cluster.** Group the library by genre, falling back to artist where genre is
   absent or uniform. Weight each cluster by listening mass (plays x recency). Keep
   the top clusters that are distinct enough to be worth a mix; **emit no mix for a
   cluster that is not** — an app with four tracks of jazz should not offer a jazz
   mix.
2. **Fill.** Roughly 60% proven engagement (played at least twice, low skip rate),
   roughly 40% novelty from the same cluster — owned but rarely or never played.
   Rediscovery is the point.
3. **Seed the RNG** with `yyyy-mm-dd` + daypart + mix index (D7).
4. **Name it** from the cluster descriptor plus the daypart: "afrobeat dusk",
   "late night guitar", "slow jams afternoon". Dayparts: early morning, morning,
   afternoon, evening, late night.
5. **Bias by hour.** Once `PlayEvents` has history, weight candidates by how much the
   user actually plays that cluster at this hour.

Cloud tracks join a mix when a drive is connected. YouTube contributes only a
separate "New for you" shelf, and only when online — a mix that cannot be played on a
plane is not a mix.

### 7.3 Cold start

A fresh install has no `PlayEvents`. Mixes then fall back to clustering on library
composition alone, with novelty drawn from `dateAdded`. Stated explicitly so the
first-run experience is designed rather than discovered.

---

## 8. Phase 5 — Navigation restructure and the Home surface

### 8.1 Shape

Four destinations in a bottom navigation bar: **Home · Library · Discover · Cloud**.

The six browse tabs (Songs, Albums, Artists, Genres, Folders, Playlists) collapse into
**Library** behind a segmented control. The mini player docks **above** the nav bar —
the standard arrangement, and it resolves where the bar should live now that
`bottomNavigationBar` is occupied.

Both nav bar and mini player are **opaque** (D9).

### 8.2 Home shelves, in order

1. Greeting + daypart
2. **Made for you** — the daily mixes (hero)
3. **Your playlists** — the explicit ask; promoted from tab 2 of 8
4. **Jump back in** — recents
5. **Rediscover** — owned, long unplayed
6. **From YouTube** — only when online

Each shelf renders nothing rather than an empty state when it has no content, so a
new install is short rather than full of apologies.

### 8.3 Migration notes

Touches all eight scaffolds from §2.2, `lib/pages/home.dart`'s `TabController`, the
coach marks (`_searchKey`, `_tabBarKey`, `_menuKey` and `CoachMarkController('home')`
reference tabs that will no longer exist), and `Routes`.

---

## 9. Phase 6 — Library redesign

Library is one screen with a segmented control over Songs / Albums / Artists /
Genres / Folders / Playlists, restyled to the Ember system in §11. Existing
behaviour that is kept as-is: sort persistence (`LibraryController.songSort`), the
alphabet fast-scroll, the pinch-zoom grid, and the drift-backed reactive streams.

`AlphabetFastScroll`, `LibraryListRow`, `PinchZoomGrid`, `SongTile` and
`SongSortButton` are restyled, not rewritten.

---

## 10. Phase 7 — Settings redesign

Fifteen sections in one scroll becomes an **index of seven categories**, each opening
a focused page, plus a search field that jumps to an individual setting.

| Category | Absorbs |
|---|---|
| Playback | App Mode, Playback, Streaming |
| Sound | Audio Enhancement, Global Equalizer, Equalizer, Tone Controls |
| Appearance | Appearance, Visualizer, Visual Style, MilkDrop |
| Library | Library |
| Cloud & Devices | Cloud Storage, Stream to Desktop |
| About & Support | About & Support |
| Advanced | anything destructive or diagnostic |

Destructive actions sit at the bottom of their page and are set apart by colour —
the pattern the research converges on.

Settings search indexes leaf settings by title, subtitle and category, so "crossfade"
finds it without knowing it lives under Playback.

---

## 11. Design system — "Ember"

Dark-first, editorial, artwork-led. Applies to Home, Library and Settings. **Not** to
the player.

### 11.1 Palette

| Token | Value | Use |
|---|---|---|
| `ground` | `#0E0E10` | app background — not pure black, which flattens depth and smears on OLED scroll |
| `surface` | `#17171A` | cards, sheets |
| `surfaceHigh` | `#202024` | raised, pressed, selected |
| `outline` | `#2C2C32` | hairlines, dividers |
| `textPrimary` | `#F5F5F7` | titles |
| `textSecondary` | `#F5F5F7` @ 62% | subtitles |
| `textTertiary` | `#F5F5F7` @ 38% | metadata |
| `ember600` | `#9C0F05` | **fills only** — filled buttons, active nav pill |
| `ember400` | `#E8503A` | **text, icons, borders on dark** |

`ember600` on `ground` measures **2.28:1**, which fails both the 3:1 floor for UI
components and the 4.5:1 floor for text. It is therefore a fill colour behind white
text — white on `ember600` measures **8.45:1** — and never a foreground colour.
`ember400` on `ground` measures **5.18:1** and passes AA for text. This distinction
is the whole reason there are two ember tokens. (Figures are sRGB relative luminance
per WCAG 2.1, computed rather than estimated.)

Light theme mirrors the ramp; `ember600` remains the fill and is legible on light
without a second token.

### 11.2 Accent from artwork

`palette_generator` (new dependency) extracts a dominant colour from the current
artwork for per-surface accenting — mix card washes, the Home header. Always
composited over `surface` and clamped for contrast, so a dark or muddy cover can
never produce unreadable text. Falls back to `ember400`.

### 11.3 Type, spacing, motion

- One bundled display face for shelf headers and mix card titles; the system face for
  body. Bundled, not fetched — the app must work offline.
- 8pt spacing scale; 4pt only inside components.
- Corner radius 24 on cards, 16 on tiles, 12 on controls.
- Depth from layered opaque surfaces and soft shadow, never from live blur (D9).
- Skeletons, not spinners, for anything async.

---

## 12. Verification

Per phase: `flutter analyze lib test` clean of new errors, `flutter test` green, and
`flutter build apk --release` succeeding.

Standing traps to respect:

- `test/widget_test.dart` "Counter increments" is untouched Flutter template
  boilerplate and **fails identically with `lib/` stashed**. It is not a regression.
- Live tests need `flutter test --tags live --run-skipped <file>`. `-P live` does not
  work, and `+0 ~1: All tests skipped` reads as green at a glance.
- `grep -rn "whenComplete(() =>" lib` before shipping — this repo has been deadlocked
  by it twice, and the arrow shorthand is what makes it invisible.

Anything not run on a physical device will be reported as **not device-tested**
rather than implied to work.

---

## 13. Risks

| Risk | Mitigation |
|---|---|
| The drift migration breaks existing libraries | `onUpgrade` is its own task with its own test, written before the tables are used |
| Splitting `YtRadioQueue` regresses three hard-won bug fixes | The eight station-identity tests move first and must stay green; the split is along the seam those fixes already established |
| New chrome reintroduces the thermal problem | Nav and mini player are opaque; no `BackdropFilter` over scrolling content |
| Phase 5 breaks coach marks and routes | Enumerated in §8.3 as work, not discovered later |
| Daily mixes look thin on a small library | Clusters that are not distinct emit no mix; shelves render nothing rather than an empty state |
| App-owned playlists diverge from MediaStore on Android | One-time import; MediaStore stays readable; app-owned is the single writer |

---

## 14. Out of scope

- The player UI (`lib/player/**`) — by instruction.
- **Local video file playback.** The app has no such feature today; video means
  YouTube music videos via `VideoRegistry` and DASH. The four combinations that
  exist are local audio, cloud audio, YouTube audio and YouTube video. If local
  video files should be playable, that is separate work.
- The crossfade-swap staleness in `_transformEvent` (§4.5).
- `lib/player/mini_player.dart`, which is dead 2023 template code with hardcoded
  strings and is referenced by nothing.
