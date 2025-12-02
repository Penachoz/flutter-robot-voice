import 'package:flutter/material.dart';

class PosePainter extends CustomPainter {
  final List<Offset> keypoints;
  final int imageWidth;
  final int imageHeight;

  PosePainter({
    required this.keypoints,
    required this.imageWidth,
    required this.imageHeight,
  });

  // Pairs de keypoints según MoveNet
  static const List<List<int>> _edges = [
    [5, 7], [7, 9],      // left arm
    [6, 8], [8, 10],     // right arm
    [5, 6],              // shoulders
    [11, 12],            // hips
    [5, 11], [6, 12],    // torso
    [11, 13], [13, 15],  // left leg
    [12, 14], [14, 16],  // right leg
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (keypoints.isEmpty || imageWidth == 0 || imageHeight == 0) {
      return;
    }

    final scaleX = size.width / imageWidth;
    final scaleY = size.height / imageHeight;

    final circlePaint = Paint()
      ..color = const Color(0xFF00FF00)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = const Color(0xFF00FF00)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Dibujar skeleton
    for (final edge in _edges) {
      final p1 = keypoints[edge[0]];
      final p2 = keypoints[edge[1]];
      if (p1 == Offset.zero || p2 == Offset.zero) continue;

      final a = Offset(p1.dx * scaleX, p1.dy * scaleY);
      final b = Offset(p2.dx * scaleX, p2.dy * scaleY);
      canvas.drawLine(a, b, linePaint);
    }

    // Dibujar puntos
    for (final p in keypoints) {
      if (p == Offset.zero) continue;
      final pt = Offset(p.dx * scaleX, p.dy * scaleY);
      canvas.drawCircle(pt, 4.0, circlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return oldDelegate.keypoints != keypoints ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight;
  }
}
