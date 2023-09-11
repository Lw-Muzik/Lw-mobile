class DSPSpeaker {
  int id;
  final String name;
  final List<int> freq;
  final List<double> gain;
  DSPSpeaker(
      {required this.id,
      required this.freq,
      required this.gain,
      required this.name});
  void setId(int x) {
    id = x;
  }
}
