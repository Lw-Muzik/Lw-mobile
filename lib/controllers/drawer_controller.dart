import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import '../exports/exports.dart';
import '../services/logger_service.dart';

class DrawerProvider extends ChangeNotifier {
  ZoomDrawerController? _controller;

  ZoomDrawerController? get controller => _controller;

  void setController(ZoomDrawerController controller) {
    _controller = controller;
    notifyListeners();
  }

  void toggleDrawer() {
    Logger.log('Toggle drawer called');
    if (_controller == null) {
      Logger.log('Controller is null!');
      return;
    }
    try {
      _controller!.toggle?.call();
      Logger.log('Toggle method called successfully');
    } catch (e) {
      Logger.log('Error toggling drawer: $e');
    }
    notifyListeners();
  }

  void openDrawer() {
    Logger.log('Open drawer called');
    if (_controller == null) {
      Logger.log('Controller is null!');
      return;
    }
    try {
      _controller!.open?.call();
      Logger.log('Open method called successfully');
    } catch (e) {
      Logger.log('Error opening drawer: $e');
    }
    notifyListeners();
  }

  void closeDrawer() {
    Logger.log('Close drawer called');
    if (_controller == null) {
      Logger.log('Controller is null!');
      return;
    }
    try {
      _controller!.close?.call();
      Logger.log('Close method called successfully');
    } catch (e) {
      Logger.log('Error closing drawer: $e');
    }
    notifyListeners();
  }
}
