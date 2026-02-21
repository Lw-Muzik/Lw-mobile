import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/AppController.dart';

class DvcVolumeOverlay extends StatelessWidget {
  const DvcVolumeOverlay({super.key});

  IconData _volumeIcon(int percent) {
    if (percent <= 0) return Icons.volume_off_rounded;
    if (percent <= 5) return Icons.volume_mute_rounded;
    if (percent <= 50) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final show = controller.showDvcOverlay;
    final percent = controller.dvcVolumePercent;
    final accent = Theme.of(context).colorScheme.primary;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: AnimatedOpacity(
                  opacity: show ? 1.0 : 0.0,
                  duration: Duration(milliseconds: show ? 150 : 500),
                  curve: Curves.easeOutCubic,
                  child: AnimatedScale(
                    scale: show ? 1.0 : 0.85,
                    duration: Duration(milliseconds: show ? 150 : 500),
                    curve: Curves.easeOutCubic,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                        child: Container(
                          width: 200,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF1A1A2E,
                            ).withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _volumeIcon(percent),
                                    color: accent,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '$percent%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: SizedBox(
                                  height: 6,
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween(
                                      begin: percent / 100,
                                      end: percent / 100,
                                    ),
                                    duration: const Duration(milliseconds: 150),
                                    curve: Curves.easeOutCubic,
                                    builder: (context, value, _) {
                                      return LinearProgressIndicator(
                                        value: value,
                                        backgroundColor: Colors.white
                                            .withValues(alpha: 0.1),
                                        valueColor: AlwaysStoppedAnimation(
                                          accent,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
