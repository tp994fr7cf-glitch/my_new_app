import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/lesson_whiteboard.dart';

class LessonWhiteboardCanvas extends StatelessWidget {
  const LessonWhiteboardCanvas({
    super.key,
    required this.strokes,
    this.inProgressStroke,
    this.drawingEnabled = false,
    this.onStrokeStart,
    this.onStrokeUpdate,
    this.onStrokeEnd,
    this.backgroundColor = Colors.white,
  });

  final List<WhiteboardStroke> strokes;
  final WhiteboardStroke? inProgressStroke;
  final bool drawingEnabled;
  final VoidCallback? onStrokeStart;
  final ValueChanged<WhiteboardPoint>? onStrokeUpdate;
  final ValueChanged<WhiteboardPoint>? onStrokeEnd;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final allStrokes = [
      ...strokes,
      if (inProgressStroke != null) inProgressStroke!,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Material(
            color: backgroundColor,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: drawingEnabled
                  ? (event) {
                      final point = _normalizePosition(event.localPosition, size);
                      onStrokeStart?.call();
                      onStrokeUpdate?.call(point);
                    }
                  : null,
              onPointerMove: drawingEnabled
                  ? (event) {
                      final point = _normalizePosition(event.localPosition, size);
                      onStrokeUpdate?.call(point);
                    }
                  : null,
              onPointerUp: drawingEnabled
                  ? (event) {
                      final point = _normalizePosition(event.localPosition, size);
                      onStrokeEnd?.call(point);
                    }
                  : null,
              onPointerCancel: drawingEnabled
                  ? (event) {
                      final point = _normalizePosition(event.localPosition, size);
                      onStrokeEnd?.call(point);
                    }
                  : null,
              child: CustomPaint(
                size: size,
                painter: _LessonWhiteboardPainter(strokes: allStrokes),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }

  static WhiteboardPoint _normalizePosition(Offset position, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return const WhiteboardPoint(x: 0, y: 0);
    }

    return WhiteboardPoint(
      x: (position.dx / size.width).clamp(0.0, 1.0),
      y: (position.dy / size.height).clamp(0.0, 1.0),
    );
  }
}

class _LessonWhiteboardPainter extends CustomPainter {
  const _LessonWhiteboardPainter({required this.strokes});

  final List<WhiteboardStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.length < 2) {
        continue;
      }

      final paint = Paint()
        ..color = Color(stroke.colorArgb)
        ..strokeWidth = stroke.strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      final first = _denormalize(stroke.points.first, size);
      path.moveTo(first.dx, first.dy);

      for (var index = 1; index < stroke.points.length; index++) {
        final point = _denormalize(stroke.points[index], size);
        path.lineTo(point.dx, point.dy);
      }

      canvas.drawPath(path, paint);
    }
  }

  Offset _denormalize(WhiteboardPoint point, Size size) {
    return Offset(
      point.x.clamp(0.0, 1.0) * size.width,
      point.y.clamp(0.0, 1.0) * size.height,
    );
  }

  @override
  bool shouldRepaint(covariant _LessonWhiteboardPainter oldDelegate) {
    return !identical(oldDelegate.strokes, strokes);
  }
}

double whiteboardStrokeWidthForSize(Size size) {
  return math.max(2, math.min(size.width, size.height) * 0.008);
}
