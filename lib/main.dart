import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/Global/index.dart';
import 'package:eq_app/Themes/AppThemes.dart';
import 'package:eq_app/controllers/AppController.dart';
import 'package:eq_app/controllers/BandController.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'Helpers/AudioHandler.dart';

// late AudioHandler audioPlayerHandler;
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Map<Permission, PermissionStatus> statuses = await [
    Permission.microphone,
    Permission.speech,
    Permission.storage,
  ].request();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );
  // audioPlayerHandler = await AudioService.init(
  //   builder: () => HypeMuzikiAudioHandler(),
  //   config: const AudioServiceConfig(
  //     androidNotificationChannelId: 'com.eq_app.channel.audio',
  //     androidNotificationChannelName: 'Music playback',
  //     androidNotificationOngoing: true,
  //     androidStopForegroundOnPause: true,
  //     androidNotificationIcon: 'mipmap/ic_launcher',
  //     // olor: 0xFF2196f3,
  //     preloadArtwork: true,
  //     androidShowNotificationBadge: true,
  //   ),
  // );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge, overlays: []);
  SystemChrome.setSystemUIOverlayStyle(overlay);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppController(),
        ),
        BlocProvider(
          create: (context) => BandController(),
        )
      ],
      child: MaterialApp(
        theme: AppThemes.fancyTheme,
        initialRoute: Routes.home,
        routes: Routes.routes(),
      ),
    ),
  );
}
