extension NumbersFormat on List<int> {
  String toTriplePadded() =>
      map((n) => n.toString().padLeft(3, '0')).join(' - ');
}
