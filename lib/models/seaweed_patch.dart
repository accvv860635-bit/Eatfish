import 'dart:ui';

class SeaweedPatch {
  const SeaweedPatch({
    required this.center,
    required this.width,
    required this.height,
    required this.swaySeed,
  });

  final Offset center;
  final double width;
  final double height;
  final double swaySeed;

  Rect get bounds =>
      Rect.fromCenter(center: center, width: width, height: height);

  bool contains(Offset position) {
    final dx = (position.dx - center.dx) / (width * .5);
    final dy = (position.dy - center.dy) / (height * .5);
    return dx * dx + dy * dy < 1;
  }
}
