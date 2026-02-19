import '/Helpers/AudioHandler.dart';
import '/Routes/routes.dart';
import '/Global/index.dart';
import '/Themes/AppThemes.dart';
import '/controllers/AppController.dart';
import '/controllers/BandController.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wiredash/wiredash.dart';
import 'package:firebase_core/firebase_core.dart';

import 'config/app_config.dart';
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
    Permission.mediaLibrary,
    Permission.storage,
    Permission.audio,
  ].request();

  await JustAudioBackground.init(
    androidNotificationIcon: "mipmap/launcher_icon",
    androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
    preloadArtwork: true,
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge, overlays: []);
  SystemChrome.setSystemUIOverlayStyle(overlay);
  // prevent the app from turning to landscape
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize SharedPreferences once before the app starts
  final prefs = await SharedPreferences.getInstance();

  runApp(
    MultiBlocProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppController(prefs)),
        ChangeNotifierProvider(create: (_) => PlaylistController()),
        ChangeNotifierProvider(create: (_) => AudioHandler()),
        ChangeNotifierProvider(create: (_) => PlayerController()),
        BlocProvider(create: (_) => BandController()),
      ],
      child: Wiredash(
        projectId: AppConfig.wiredashProjectId,
        secret: AppConfig.wiredashSecret,
        options: const WiredashOptionsData(locale: Locale('en')),
        child: MaterialApp(
          theme: AppThemes.fancyTheme,
          initialRoute: Routes.loader,
          routes: Routes.routes(),
        ),
      ),
    ),
  );
}
