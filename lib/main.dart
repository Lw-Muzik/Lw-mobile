import 'package:eq_app/Helpers/AudioHandler.dart';
import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/Global/index.dart';
import 'package:eq_app/Themes/AppThemes.dart';
import 'package:eq_app/controllers/AppController.dart';
import 'package:eq_app/controllers/BandController.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:wiredash/wiredash.dart';
import 'package:firebase_core/firebase_core.dart';

import 'controllers/PlayerController.dart';
import 'controllers/PlaylistController.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FlutterError.onError = (errorDetails) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
  };
  // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
  await [
    Permission.storage,
    Permission.audio,
    // Permission.microphone,
  ].request();
  // var status = await Permission.storage.status;
  // if (status.isGranted) {

  // }

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
  // SystemSound.play(SystemSoundType.alert);
  // prevent the app from turning to landscape
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // request for permission to read audio files
  // SharedPreferences prefs = await SharedPreferences.getInstance();
  // prefs.clear();
  runApp(
    MultiBlocProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppController(),
        ),
        ChangeNotifierProvider(create: (context) => PlaylistController()),
        ChangeNotifierProvider(create: (context) => AudioHandler()),
        ChangeNotifierProvider(create: (context) => PlayerController()),
        BlocProvider(
          create: (context) => BandController(),
        )
      ],
      child: Wiredash(
        projectId: "hype-muzik-q8wp9st",
        secret: "UB-v1DeJeOBqg3yxM5lOqEhoSsjrq-HM",
        options: const WiredashOptionsData(
          locale: Locale('en'),
        ),
        child: MaterialApp(
          theme: AppThemes.fancyTheme,
          initialRoute: Routes.loader,
          routes: Routes.routes(),
        ),
      ),
    ),
  );
}
