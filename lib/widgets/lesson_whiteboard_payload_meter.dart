import 'dart:async';

import 'package:flutter/material.dart';

import '../models/lesson_payload_size_validator.dart';
import '../models/lesson_whiteboard_board_set.dart';

const Duration lessonWhiteboardPayloadMeterInterval = Duration(seconds: 15);

class LessonWhiteboardPayloadMeter extends StatefulWidget {
  const LessonWhiteboardPayloadMeter({
    super.key,
    required this.boardSet,
    this.scopeKey,
  });

  final BoardSet boardSet;
  final Object? scopeKey;

  @override
  State<LessonWhiteboardPayloadMeter> createState() =>
      _LessonWhiteboardPayloadMeterState();
}

class _LessonWhiteboardPayloadMeterState
    extends State<LessonWhiteboardPayloadMeter> {
  Timer? _timer;
  late int _usedBytes;

  @override
  void initState() {
    super.initState();
    _usedBytes = _measureBytes();
    _timer = Timer.periodic(lessonWhiteboardPayloadMeterInterval, (_) {
      if (!mounted) {
        return;
      }
      final nextBytes = _measureBytes();
      if (nextBytes == _usedBytes) {
        return;
      }
      setState(() {
        _usedBytes = nextBytes;
      });
    });
  }

  @override
  void didUpdateWidget(covariant LessonWhiteboardPayloadMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeKey != widget.scopeKey) {
      final nextBytes = _measureBytes();
      if (nextBytes != _usedBytes) {
        setState(() {
          _usedBytes = nextBytes;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int _measureBytes() {
    return estimateSerializedUtf8JsonBytes(widget.boardSet.toMap());
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          formatLessonPayloadUsageFraction(_usedBytes),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}
