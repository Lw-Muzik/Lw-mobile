import 'package:flutter_bloc/flutter_bloc.dart';

class BandController extends Cubit<List<int>> {
  BandController() : super(bands);

  static List<int> bands = [0, 0, 0, 0, 0];
  setBands(List<int> b) {
    emit(b);
  }
}
