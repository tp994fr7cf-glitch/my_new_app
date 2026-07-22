import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/lesson_whiteboard.dart';
import '../models/lesson_whiteboard_board_set.dart';

const double lessonWhiteboardAspectRatio = 4 / 3;
const double lessonWhiteboardMaxWidth = 640;
const double lessonWhiteboardCompactMaxWidth =
    220 * lessonWhiteboardAspectRatio;

enum LessonWhiteboardViewportChangePhase { start, update, end }

class LessonWhiteboardViewportChange {
  const LessonWhiteboardViewportChange({
    required this.viewport,
    required this.phase,
  });

  final LessonWhiteboardViewport viewport;
  final LessonWhiteboardViewportChangePhase phase;
}

class LessonWhiteboardCanvas extends StatefulWidget {
  const LessonWhiteboardCanvas({
    super.key,
    required this.strokes,
    this.inProgressStroke,
    this.drawingEnabled = false,
    this.onStrokeStart,
    this.onStrokeUpdate,
    this.onStrokeEnd,
    this.onStrokeCancel,
    this.viewport,
    this.onViewportChanged,
    this.viewportInteractionEnabled = true,
    this.maxWidth = lessonWhiteboardMaxWidth,
    this.backgroundColor = Colors.white,
  });

  final List<WhiteboardStroke> strokes;
  final WhiteboardStroke? inProgressStroke;
  final bool drawingEnabled;
  final VoidCallback? onStrokeStart;
  final ValueChanged<WhiteboardPoint>? onStrokeUpdate;
  final ValueChanged<WhiteboardPoint>? onStrokeEnd;
  final VoidCallback? onStrokeCancel;
  final LessonWhiteboardViewport? viewport;
  final ValueChanged<LessonWhiteboardViewportChange>? onViewportChanged;
  final bool viewportInteractionEnabled;
  final double maxWidth;
  final Color backgroundColor;

  @override
  State<LessonWhiteboardCanvas> createState() => _LessonWhiteboardCanvasState();
}

class _LessonWhiteboardCanvasState extends State<LessonWhiteboardCanvas> {
  final Map<int, Offset> _pointerPositions = {};
  late LessonWhiteboardViewport _viewport;
  Timer? _minimapHideTimer;
  Timer? _scrollInteractionEndTimer;
  bool _minimapVisible = false;
  bool _viewInteractionActive = false;
  bool _suppressUntilAllPointersUp = false;
  int? _drawingPointer;
  int? _panPointer;
  Offset? _lastFocalPoint;
  double? _lastPointerSpan;

  @override
  void initState() {
    super.initState();
    _viewport = widget.viewport ?? LessonWhiteboardViewport.full;
  }

  @override
  void didUpdateWidget(covariant LessonWhiteboardCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controlledViewport = widget.viewport;
    if (controlledViewport != null &&
        controlledViewport != _viewport &&
        !_viewInteractionActive) {
      _viewport = controlledViewport;
      _showMinimap(scheduleHide: true);
    }
  }

  @override
  void dispose() {
    _minimapHideTimer?.cancel();
    _scrollInteractionEndTimer?.cancel();
    super.dispose();
  }

  void _showMinimap({required bool scheduleHide}) {
    _minimapHideTimer?.cancel();
    if (!_minimapVisible && mounted) {
      setState(() => _minimapVisible = true);
    } else {
      _minimapVisible = true;
    }
    if (scheduleHide) {
      _minimapHideTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _minimapVisible = false);
        }
      });
    }
  }

  void _beginViewInteraction() {
    if (_viewInteractionActive) {
      return;
    }
    _viewInteractionActive = true;
    _showMinimap(scheduleHide: false);
    widget.onViewportChanged?.call(
      LessonWhiteboardViewportChange(
        viewport: _viewport,
        phase: LessonWhiteboardViewportChangePhase.start,
      ),
    );
  }

  void _setViewport(LessonWhiteboardViewport viewport) {
    if (viewport == _viewport) {
      return;
    }
    setState(() => _viewport = viewport);
    _showMinimap(scheduleHide: false);
    widget.onViewportChanged?.call(
      LessonWhiteboardViewportChange(
        viewport: viewport,
        phase: LessonWhiteboardViewportChangePhase.update,
      ),
    );
  }

  void _endViewInteraction() {
    if (!_viewInteractionActive) {
      return;
    }
    _viewInteractionActive = false;
    _scrollInteractionEndTimer = null;
    widget.onViewportChanged?.call(
      LessonWhiteboardViewportChange(
        viewport: _viewport,
        phase: LessonWhiteboardViewportChangePhase.end,
      ),
    );
    _showMinimap(scheduleHide: true);
  }

  void _applySingleViewportChange(LessonWhiteboardViewport viewport) {
    _beginViewInteraction();
    _setViewport(viewport);
    _endViewInteraction();
  }

  WhiteboardPoint _boardPoint(Offset position, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return const WhiteboardPoint(x: 0, y: 0);
    }
    return WhiteboardPoint(
      x:
          (_viewport.centerX +
                  (((position.dx / size.width) - 0.5) / _viewport.scale))
              .clamp(0.0, 1.0),
      y:
          (_viewport.centerY +
                  (((position.dy / size.height) - 0.5) / _viewport.scale))
              .clamp(0.0, 1.0),
    );
  }

  Offset _currentFocalPoint() {
    final positions = _pointerPositions.values.take(2).toList();
    if (positions.length < 2) {
      return positions.isEmpty ? Offset.zero : positions.single;
    }
    return Offset(
      (positions[0].dx + positions[1].dx) / 2,
      (positions[0].dy + positions[1].dy) / 2,
    );
  }

  double _currentPointerSpan() {
    final positions = _pointerPositions.values.take(2).toList();
    if (positions.length < 2) {
      return 0;
    }
    return (positions[0] - positions[1]).distance;
  }

  void _startMultiPointerInteraction() {
    if (_drawingPointer != null) {
      widget.onStrokeCancel?.call();
    }
    _drawingPointer = null;
    _panPointer = null;
    _beginViewInteraction();
    _lastFocalPoint = _currentFocalPoint();
    _lastPointerSpan = _currentPointerSpan();
  }

  void _updateMultiPointerInteraction(Size size) {
    final previousFocal = _lastFocalPoint;
    final previousSpan = _lastPointerSpan;
    final focal = _currentFocalPoint();
    final span = _currentPointerSpan();
    if (previousFocal == null ||
        previousSpan == null ||
        previousSpan <= 0 ||
        span <= 0) {
      _lastFocalPoint = focal;
      _lastPointerSpan = span;
      return;
    }
    final boardPointAtPreviousFocal = _boardPoint(previousFocal, size);
    final nextScale = (_viewport.scale * (span / previousSpan))
        .clamp(
          minLessonWhiteboardViewportScale,
          maxLessonWhiteboardViewportScale,
        )
        .toDouble();
    final nextViewport = LessonWhiteboardViewport.normalized(
      centerX:
          boardPointAtPreviousFocal.x -
          (((focal.dx / size.width) - 0.5) / nextScale),
      centerY:
          boardPointAtPreviousFocal.y -
          (((focal.dy / size.height) - 0.5) / nextScale),
      scale: nextScale,
    );
    _setViewport(nextViewport);
    _lastFocalPoint = focal;
    _lastPointerSpan = span;
  }

  void _updateSinglePointerPan(Offset position, Size size) {
    final previous = _lastFocalPoint;
    if (previous == null) {
      _lastFocalPoint = position;
      return;
    }
    final dragDelta = position - previous;
    if (!_viewInteractionActive && dragDelta.distance < kTouchSlop) {
      return;
    }
    _beginViewInteraction();
    final nextViewport = LessonWhiteboardViewport.normalized(
      centerX:
          _viewport.centerX - (dragDelta.dx / (size.width * _viewport.scale)),
      centerY:
          _viewport.centerY - (dragDelta.dy / (size.height * _viewport.scale)),
      scale: _viewport.scale,
    );
    _setViewport(nextViewport);
    _lastFocalPoint = position;
  }

  void _handlePointerDown(PointerDownEvent event, Size size) {
    if (_scrollInteractionEndTimer != null) {
      _scrollInteractionEndTimer?.cancel();
      _scrollInteractionEndTimer = null;
      _endViewInteraction();
    }
    _pointerPositions[event.pointer] = event.localPosition;
    if (!widget.viewportInteractionEnabled) {
      if (widget.drawingEnabled && _pointerPositions.length == 1) {
        _drawingPointer = event.pointer;
        widget.onStrokeStart?.call();
        widget.onStrokeUpdate?.call(_boardPoint(event.localPosition, size));
      }
      return;
    }
    if (_pointerPositions.length >= 2) {
      _startMultiPointerInteraction();
      return;
    }
    if (_suppressUntilAllPointersUp) {
      return;
    }
    if (widget.drawingEnabled) {
      _drawingPointer = event.pointer;
      widget.onStrokeStart?.call();
      widget.onStrokeUpdate?.call(_boardPoint(event.localPosition, size));
    } else if (_viewport.scale > minLessonWhiteboardViewportScale) {
      _panPointer = event.pointer;
      _lastFocalPoint = event.localPosition;
    }
  }

  void _handlePointerMove(PointerMoveEvent event, Size size) {
    if (!_pointerPositions.containsKey(event.pointer)) {
      return;
    }
    _pointerPositions[event.pointer] = event.localPosition;
    if (widget.viewportInteractionEnabled && _pointerPositions.length >= 2) {
      _updateMultiPointerInteraction(size);
      return;
    }
    if (_suppressUntilAllPointersUp) {
      return;
    }
    if (_drawingPointer == event.pointer && widget.drawingEnabled) {
      widget.onStrokeUpdate?.call(_boardPoint(event.localPosition, size));
    } else if (_panPointer == event.pointer &&
        widget.viewportInteractionEnabled) {
      _updateSinglePointerPan(event.localPosition, size);
    }
  }

  void _handlePointerEnd(
    PointerEvent event,
    Size size, {
    required bool cancelled,
  }) {
    final hadMultiplePointers = _pointerPositions.length >= 2;
    if (_drawingPointer == event.pointer) {
      if (cancelled) {
        widget.onStrokeCancel?.call();
      } else {
        widget.onStrokeEnd?.call(_boardPoint(event.localPosition, size));
      }
      _drawingPointer = null;
    }
    if (_panPointer == event.pointer) {
      _panPointer = null;
      _endViewInteraction();
    }
    _pointerPositions.remove(event.pointer);
    if (hadMultiplePointers && _pointerPositions.length < 2) {
      _endViewInteraction();
      _suppressUntilAllPointersUp = true;
    }
    if (_pointerPositions.isEmpty) {
      _suppressUntilAllPointersUp = false;
      _lastFocalPoint = null;
      _lastPointerSpan = null;
    }
  }

  double _nextZoomLevel({required bool zoomIn}) {
    const levels = <double>[1, 2, 4, 8];
    if (zoomIn) {
      return levels.firstWhere(
        (level) => level > _viewport.scale + 0.001,
        orElse: () => maxLessonWhiteboardViewportScale,
      );
    }
    return levels.reversed.firstWhere(
      (level) => level < _viewport.scale - 0.001,
      orElse: () => minLessonWhiteboardViewportScale,
    );
  }

  void _zoomAt(Offset focalPoint, Size size, double nextScale) {
    final boardPointAtFocal = _boardPoint(focalPoint, size);
    _applySingleViewportChange(
      LessonWhiteboardViewport.normalized(
        centerX:
            boardPointAtFocal.x -
            (((focalPoint.dx / size.width) - 0.5) / nextScale),
        centerY:
            boardPointAtFocal.y -
            (((focalPoint.dy / size.height) - 0.5) / nextScale),
        scale: nextScale,
      ),
    );
  }

  void _handlePointerSignal(PointerSignalEvent event, Size size) {
    if (!widget.viewportInteractionEnabled || event is! PointerScrollEvent) {
      return;
    }
    final zoomIn = event.scrollDelta.dy < 0;
    final factor = zoomIn ? 1.2 : 1 / 1.2;
    final nextScale = (_viewport.scale * factor)
        .clamp(
          minLessonWhiteboardViewportScale,
          maxLessonWhiteboardViewportScale,
        )
        .toDouble();
    if (nextScale != _viewport.scale) {
      final boardPointAtFocal = _boardPoint(event.localPosition, size);
      _beginViewInteraction();
      _setViewport(
        LessonWhiteboardViewport.normalized(
          centerX:
              boardPointAtFocal.x -
              (((event.localPosition.dx / size.width) - 0.5) / nextScale),
          centerY:
              boardPointAtFocal.y -
              (((event.localPosition.dy / size.height) - 0.5) / nextScale),
          scale: nextScale,
        ),
      );
      _scrollInteractionEndTimer?.cancel();
      _scrollInteractionEndTimer = Timer(
        const Duration(milliseconds: 160),
        _endViewInteraction,
      );
    }
  }

  Widget _buildControls(Size size) {
    final canZoomOut =
        _viewport.scale > minLessonWhiteboardViewportScale + 0.001;
    final canZoomIn =
        _viewport.scale < maxLessonWhiteboardViewportScale - 0.001;
    return Positioned(
      top: 8,
      right: 8,
      child: Material(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const ValueKey('whiteboard-zoom-out'),
              tooltip: '縮小',
              visualDensity: VisualDensity.compact,
              color: Colors.white,
              onPressed: canZoomOut
                  ? () => _zoomAt(
                      size.center(Offset.zero),
                      size,
                      _nextZoomLevel(zoomIn: false),
                    )
                  : null,
              icon: const Icon(Icons.remove),
            ),
            Text(
              '${_viewport.scale.toStringAsFixed(_viewport.scale % 1 == 0 ? 0 : 1)}x',
              key: const ValueKey('whiteboard-zoom-label'),
              style: const TextStyle(color: Colors.white),
            ),
            IconButton(
              key: const ValueKey('whiteboard-zoom-in'),
              tooltip: '拡大',
              visualDensity: VisualDensity.compact,
              color: Colors.white,
              onPressed: canZoomIn
                  ? () => _zoomAt(
                      size.center(Offset.zero),
                      size,
                      _nextZoomLevel(zoomIn: true),
                    )
                  : null,
              icon: const Icon(Icons.add),
            ),
            IconButton(
              key: const ValueKey('whiteboard-zoom-reset'),
              tooltip: '元の大きさに戻す',
              visualDensity: VisualDensity.compact,
              color: Colors.white,
              onPressed: canZoomOut
                  ? () => _applySingleViewportChange(
                      LessonWhiteboardViewport.full,
                    )
                  : null,
              icon: const Icon(Icons.center_focus_strong),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allStrokes = [
      ...widget.strokes,
      if (widget.inProgressStroke != null) widget.inProgressStroke!,
    ];
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: AspectRatio(
          key: const ValueKey('whiteboard-aspect-ratio'),
          aspectRatio: lessonWhiteboardAspectRatio,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              final minimapWidth = math.min(120.0, size.width * 0.32);
              final minimapSize = Size(
                minimapWidth,
                minimapWidth / lessonWhiteboardAspectRatio,
              );
              return Semantics(
                label: 'ホワイトボード',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Material(
                    color: widget.backgroundColor,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RawGestureDetector(
                          gestures: {
                            _WhiteboardGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                  _WhiteboardGestureRecognizer
                                >(_WhiteboardGestureRecognizer.new, (
                                  recognizer,
                                ) {
                                  recognizer.acceptSinglePointer =
                                      widget.drawingEnabled ||
                                      (widget.viewportInteractionEnabled &&
                                          _viewport.scale >
                                              minLessonWhiteboardViewportScale);
                                }),
                          },
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (event) =>
                                _handlePointerDown(event, size),
                            onPointerMove: (event) =>
                                _handlePointerMove(event, size),
                            onPointerUp: (event) => _handlePointerEnd(
                              event,
                              size,
                              cancelled: false,
                            ),
                            onPointerCancel: (event) =>
                                _handlePointerEnd(event, size, cancelled: true),
                            onPointerSignal: (event) =>
                                _handlePointerSignal(event, size),
                            child: CustomPaint(
                              size: size,
                              painter: _LessonWhiteboardPainter(
                                strokes: allStrokes,
                                viewport: _viewport,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        if (widget.viewportInteractionEnabled)
                          _buildControls(size),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              key: const ValueKey('whiteboard-minimap'),
                              opacity: _minimapVisible ? 1 : 0,
                              duration: const Duration(milliseconds: 180),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: widget.backgroundColor.withValues(
                                    alpha: 0.92,
                                  ),
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: const [
                                    BoxShadow(
                                      blurRadius: 4,
                                      color: Color(0x33000000),
                                    ),
                                  ],
                                ),
                                child: SizedBox.fromSize(
                                  size: minimapSize,
                                  child: CustomPaint(
                                    painter: _LessonWhiteboardMinimapPainter(
                                      strokes: allStrokes,
                                      viewport: _viewport,
                                      viewportColor: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WhiteboardGestureRecognizer extends OneSequenceGestureRecognizer {
  bool acceptSinglePointer = false;
  final Set<int> _trackedPointers = {};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer);
    _trackedPointers.add(event.pointer);
    if (acceptSinglePointer || _trackedPointers.length >= 2) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
      _trackedPointers.remove(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _trackedPointers.clear();
  }

  @override
  String get debugDescription => 'whiteboard';
}

class _LessonWhiteboardPainter extends CustomPainter {
  const _LessonWhiteboardPainter({
    required this.strokes,
    required this.viewport,
  });

  final List<WhiteboardStroke> strokes;
  final LessonWhiteboardViewport viewport;

  @override
  void paint(Canvas canvas, Size size) {
    _paintWhiteboardStrokes(
      canvas: canvas,
      size: size,
      strokes: strokes,
      viewport: viewport,
      scaleStrokeWidth: true,
    );
  }

  @override
  bool shouldRepaint(covariant _LessonWhiteboardPainter oldDelegate) {
    return oldDelegate.viewport != viewport ||
        _strokeListVisualsChanged(oldDelegate.strokes, strokes);
  }
}

class _LessonWhiteboardMinimapPainter extends CustomPainter {
  const _LessonWhiteboardMinimapPainter({
    required this.strokes,
    required this.viewport,
    required this.viewportColor,
  });

  final List<WhiteboardStroke> strokes;
  final LessonWhiteboardViewport viewport;
  final Color viewportColor;

  @override
  void paint(Canvas canvas, Size size) {
    _paintWhiteboardStrokes(
      canvas: canvas,
      size: size,
      strokes: strokes,
      viewport: LessonWhiteboardViewport.full,
      scaleStrokeWidth: false,
    );
    final viewportRect = Rect.fromLTWH(
      viewport.left * size.width,
      viewport.top * size.height,
      viewport.width * size.width,
      viewport.height * size.height,
    );
    canvas.drawRect(
      viewportRect,
      Paint()
        ..color = viewportColor.withValues(alpha: 0.16)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      viewportRect,
      Paint()
        ..color = viewportColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _LessonWhiteboardMinimapPainter oldDelegate) {
    return oldDelegate.viewport != viewport ||
        oldDelegate.viewportColor != viewportColor ||
        _strokeListVisualsChanged(oldDelegate.strokes, strokes);
  }
}

void _paintWhiteboardStrokes({
  required Canvas canvas,
  required Size size,
  required List<WhiteboardStroke> strokes,
  required LessonWhiteboardViewport viewport,
  required bool scaleStrokeWidth,
}) {
  for (final stroke in strokes) {
    if (stroke.points.length < 2) {
      continue;
    }
    final paint = Paint()
      ..color = Color(stroke.colorArgb)
      ..strokeWidth = scaleStrokeWidth
          ? stroke.strokeWidth * viewport.scale
          : math.max(0.7, stroke.strokeWidth * 0.35)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    final first = _viewportPosition(stroke.points.first, size, viewport);
    path.moveTo(first.dx, first.dy);
    for (var index = 1; index < stroke.points.length; index++) {
      final point = _viewportPosition(stroke.points[index], size, viewport);
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }
}

Offset _viewportPosition(
  WhiteboardPoint point,
  Size size,
  LessonWhiteboardViewport viewport,
) {
  return Offset(
    (point.x.clamp(0.0, 1.0) - viewport.left) * size.width * viewport.scale,
    (point.y.clamp(0.0, 1.0) - viewport.top) * size.height * viewport.scale,
  );
}

bool _strokeListVisualsChanged(
  List<WhiteboardStroke> previous,
  List<WhiteboardStroke> next,
) {
  if (identical(previous, next)) {
    return false;
  }
  if (previous.length != next.length) {
    return true;
  }
  for (var index = 0; index < next.length; index++) {
    if (_strokeVisualsChanged(previous[index], next[index])) {
      return true;
    }
  }
  return false;
}

bool _strokeVisualsChanged(WhiteboardStroke previous, WhiteboardStroke next) {
  if (previous.id != next.id ||
      previous.colorArgb != next.colorArgb ||
      previous.strokeWidth != next.strokeWidth ||
      previous.points.length != next.points.length) {
    return true;
  }
  if (previous.points.isEmpty) {
    return false;
  }
  final previousLast = previous.points.last;
  final nextLast = next.points.last;
  return previousLast.x != nextLast.x || previousLast.y != nextLast.y;
}

double whiteboardStrokeWidthForSize(Size size) {
  return math.max(2, math.min(size.width, size.height) * 0.008);
}
