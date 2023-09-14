import 'dart:ui';

import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/Global/index.dart';
import 'package:eq_app/Themes/AppThemes.dart';
import 'package:eq_app/controllers/AppController.dart';
import 'package:eq_app/controllers/BandController.dart';
import 'package:eq_app/controllers/ThemeController.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge, overlays: []);
  SystemChrome.setSystemUIOverlayStyle(overlay);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppController()),
        BlocProvider(create: (context) => BandController())
      ],
      child: MaterialApp(
        theme: AppThemes.fancyTheme,
        initialRoute: Routes.home,
        routes: Routes.routes(),
      ),
    ),
  );
}
