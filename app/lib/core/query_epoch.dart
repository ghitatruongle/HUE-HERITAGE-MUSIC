class QueryEpoch {
  int _value = 0;

  int get value => _value;

  int next() => ++_value;

  bool isCurrent(int epoch) => epoch == _value;
}
