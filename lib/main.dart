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
import 'package:shared_preferences/shared_preferences.dart';

import 'Helpers/fileloader.dart';
import 'controllers/PlaylistController.dart';

// late AudioHandler audioPlayerHandler;
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences prefs = await SharedPreferences.getInstance();

  await JustAudioBackground.init(
    androidNotificationIcon: "mipmap/launcher_icon",
    androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    // androidNotificationOngoing: true,
    preloadArtwork: true,
    androidStopForegroundOnPause: false,
    artDownscaleHeight: 200,
    artDownscaleWidth: 200,
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge, overlays: []);
  SystemChrome.setSystemUIOverlayStyle(overlay);
  SystemSound.play(SystemSoundType.alert);
  // prevent the app from turning to landscape
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
// request for permission to read audio files
  var status = await Permission.storage.status;
  if (!status.isGranted) {
    await Permission.storage.request();
  }
  // check if artwork is already loaded
  if (prefs.getBool("artworkLoaded") == null) {
    // load artwork
    await fetchMetaData();
    prefs.setBool("artworkLoaded", true);
  }
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppController(),
        ),
        ChangeNotifierProvider(create: (context) => PlaylistController()),
        BlocProvider(
          create: (context) => BandController(),
        )
      ],
      child: MaterialApp(
        theme: AppThemes.fancyTheme,
        initialRoute: prefs.getBool("artworkLoaded") == true
            ? Routes.home
            : Routes.loader,
        routes: Routes.routes(),
      ),
    ),
  );
}
