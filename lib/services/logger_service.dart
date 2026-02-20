import 'dart:async';
import 'dart:developer' as console;

class Logger {
  static void log(String message) {
    console.log(
      message,
      name: 'LoggerService',
      time: DateTime.now(),
      error: null,
      stackTrace: null,
      zone: Zone.root,
    );
  }
}
