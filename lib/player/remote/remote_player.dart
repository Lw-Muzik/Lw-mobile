/// The full player while another device is the player.
///
/// Everything here is that device's: its track, its queue, its progress. The
/// controls send commands to it. EQ and DSP stay on this phone; lyrics and the
/// visualiser belong to the other device, and a card says so rather than
/// showing stale local ones.
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:eq_app/Themes/app_fonts.dart';
import 'package:eq_app/services/connect/connect_protocol.dart';
import 'package:eq_app/services/connect/hype_connect.dart';
import 'package:eq_app/services/connect/remote/connect_remote_session.dart';
import 'package:eq_app/themes/ember.dart';
import 'connect_device_picker.dart';
import 'remote_scope.dart';

class RemotePlayerView extends StatelessWidget {
  const RemotePlayerView({super.key, required this.remote});

  final RemoteNowPlaying remote;

  @override
  Widget build(BuildContext context) {
    final session = HypeConnect.instance.session!;
    final artUrl = switch (remote.track) {
      YtTrackRef(:final artUrl) => artUrl,
      _ => null,
    };
    final width = MediaQuery.of(context).size.width;
    final artSize = (width - 64).clamp(180.0, 360.0);
    return Scaffold(
      backgroundColor: Ember.ground,
      body: Stack(
        children: [
          if (artUrl != null)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Image.network(
                  artUrl,
                  fit: BoxFit.cover,
                  cacheWidth: 120,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Ember.ground.withValues(alpha: 0.55),
                    Ember.ground.withValues(alpha: 0.92),
                    Ember.ground,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _Header(remote: remote),
                const SizedBox(height: 12),
                Center(
                  child: RemoteArt(
                    track: remote.track,
                    size: artSize,
                    radius: Ember.radiusCard,
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        remoteTitleOf(remote.track),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.displayStyle(
                          fontSize: 24,
                          color: Ember.textPrimary,
                        ),
                      ),
                      if (remoteArtistOf(remote.track) != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          remoteArtistOf(remote.track)!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Ember.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _Progress(session: session),
                const SizedBox(height: 8),
                _Transport(session: session, remote: remote),
                const SizedBox(height: 8),
                _VolumeRow(session: session, remote: remote),
                const SizedBox(height: 20),
                _LyricsCard(deviceName: remote.device.name),
                const SizedBox(height: 20),
                _UpNext(session: session, remote: remote),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.remote});

  final RemoteNowPlaying remote;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Ember.textPrimary,
              size: 28,
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'PLAYING ON',
                  style: TextStyle(
                    color: Ember.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(kConnectGlyph, size: 14, color: Ember.accent),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        remote.device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Ember.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const ConnectPickerButton(size: 24),
        ],
      ),
    );
  }
}

/// Live progress: ticks locally between the other device's reports.
class _Progress extends StatefulWidget {
  const _Progress({required this.session});

  final ConnectRemoteSession session;

  @override
  State<_Progress> createState() => _ProgressState();
}

class _ProgressState extends State<_Progress> {
  Timer? _tick;
  double? _dragging;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && _dragging == null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remote = widget.session.nowPlaying();
    if (remote == null) return const SizedBox.shrink();
    final duration = remote.durationMs ?? 0;
    final position = _dragging?.round() ?? remote.positionMs;
    final max = duration > 0 ? duration.toDouble() : 1.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: Ember.accent,
              inactiveTrackColor: Ember.outline,
              thumbColor: Ember.accent,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: position.clamp(0, max.toInt()).toDouble(),
              max: max,
              onChanged: duration > 0
                  ? (v) => setState(() => _dragging = v)
                  : null,
              onChangeEnd: (v) {
                setState(() => _dragging = null);
                widget.session.seek(v.round());
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatMs(position),
                  style: TextStyle(color: Ember.textTertiary, fontSize: 12),
                ),
                Text(
                  duration > 0 ? formatMs(duration) : '--:--',
                  style: TextStyle(color: Ember.textTertiary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.session, required this.remote});

  final ConnectRemoteSession session;
  final RemoteNowPlaying remote;

  @override
  Widget build(BuildContext context) {
    final repeatIcon = remote.repeat == ConnectRepeat.one
        ? Icons.repeat_one_rounded
        : Icons.repeat_rounded;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Toggle(
          icon: Icons.shuffle_rounded,
          on: remote.shuffle,
          onPressed: () => session.shuffle(!remote.shuffle),
        ),
        const SizedBox(width: 12),
        _Skip(icon: Icons.skip_previous_rounded, onPressed: () => session.prev()),
        const SizedBox(width: 16),
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            remote.playing ? session.pause() : session.resume();
          },
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Ember.accent,
              shape: BoxShape.circle,
            ),
            // Gold is a solid fill here, so the glyph on it is dark.
            child: Icon(
              remote.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 38,
              color: Ember.ground,
            ),
          ),
        ),
        const SizedBox(width: 16),
        _Skip(icon: Icons.skip_next_rounded, onPressed: () => session.next()),
        const SizedBox(width: 12),
        _Toggle(
          icon: repeatIcon,
          on: remote.repeat != ConnectRepeat.off,
          onPressed: () => session.repeat(switch (remote.repeat) {
            ConnectRepeat.off => ConnectRepeat.all,
            ConnectRepeat.all => ConnectRepeat.one,
            ConnectRepeat.one => ConnectRepeat.off,
          }),
        ),
      ],
    );
  }
}

class _Skip extends StatelessWidget {
  const _Skip({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onPressed,
        iconSize: 36,
        icon: Icon(icon, color: Ember.textPrimary),
      );
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.icon, required this.on, required this.onPressed});

  final IconData icon;
  final bool on;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: on ? Ember.accent : Ember.textTertiary),
      );
}

class _VolumeRow extends StatefulWidget {
  const _VolumeRow({required this.session, required this.remote});

  final ConnectRemoteSession session;
  final RemoteNowPlaying remote;

  @override
  State<_VolumeRow> createState() => _VolumeRowState();
}

class _VolumeRowState extends State<_VolumeRow> {
  double? _dragging;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Widget build(BuildContext context) {
    final value = (_dragging ?? widget.remote.volume).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Icon(Icons.volume_mute_rounded, size: 18, color: Ember.textTertiary),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                activeTrackColor: Ember.textSecondary,
                inactiveTrackColor: Ember.outline,
                thumbColor: Ember.textPrimary,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              ),
              child: Slider(
                value: value,
                onChanged: (v) {
                  setState(() => _dragging = v);
                  final now = DateTime.now();
                  if (now.difference(_lastSent) > const Duration(milliseconds: 150)) {
                    _lastSent = now;
                    widget.session.volume(v);
                  }
                },
                onChangeEnd: (v) {
                  setState(() => _dragging = null);
                  widget.session.volume(v);
                },
              ),
            ),
          ),
          Icon(Icons.volume_up_rounded, size: 18, color: Ember.textTertiary),
        ],
      ),
    );
  }
}

class _LyricsCard extends StatelessWidget {
  const _LyricsCard({required this.deviceName});

  final String deviceName;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Ember.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(Ember.radiusTile),
        border: Border.all(color: Ember.outline),
      ),
      child: Row(
        children: [
          Icon(Icons.lyrics_rounded, color: Ember.textTertiary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Lyrics are on $deviceName',
              style: TextStyle(color: Ember.textSecondary, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpNext extends StatelessWidget {
  const _UpNext({required this.session, required this.remote});

  final ConnectRemoteSession session;
  final RemoteNowPlaying remote;

  @override
  Widget build(BuildContext context) {
    if (remote.queue.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text('UP NEXT', style: Ember.shelfTitle(context)),
        ),
        const SizedBox(height: 8),
        for (final entry in remote.queue)
          InkWell(
            onTap: () => session.jump(entry.uid),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 6),
              child: Row(
                children: [
                  RemoteArt(track: entry.track, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          remoteTitleOf(entry.track),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Ember.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        if (remoteArtistOf(entry.track) != null)
                          Text(
                            remoteArtistOf(entry.track)!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Ember.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
