import 'lesson_media_timeline.dart';

int? parseLessonDurationLabel(String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final minuteSecondPattern = RegExp(r'^(\d+)分(\d+)秒$');
  final minuteSecondMatch = minuteSecondPattern.firstMatch(trimmed);
  if (minuteSecondMatch != null) {
    final minutes = int.tryParse(minuteSecondMatch.group(1)!);
    final seconds = int.tryParse(minuteSecondMatch.group(2)!);
    if (minutes != null && seconds != null) {
      return minutes * 60 + seconds;
    }
  }

  final minuteOnlyPattern = RegExp(r'^(\d+)分$');
  final minuteOnlyMatch = minuteOnlyPattern.firstMatch(trimmed);
  if (minuteOnlyMatch != null) {
    final minutes = int.tryParse(minuteOnlyMatch.group(1)!);
    if (minutes != null) {
      return minutes * 60;
    }
  }

  final secondOnlyPattern = RegExp(r'^(\d+)秒$');
  final secondOnlyMatch = secondOnlyPattern.firstMatch(trimmed);
  if (secondOnlyMatch != null) {
    return int.tryParse(secondOnlyMatch.group(1)!);
  }

  return null;
}

int resolveLessonMediaDurationSec({
  required Duration? playerDuration,
  required int mediaDurationSec,
  required String durationLabel,
}) {
  final fromPlayer = playerDuration?.inSeconds ?? 0;
  if (fromPlayer > 0) {
    return fromPlayer;
  }
  if (mediaDurationSec > 0) {
    return mediaDurationSec;
  }
  return parseLessonDurationLabel(durationLabel) ?? 0;
}

int resolveTimelineDurationSec({
  required LessonMediaTimeline timeline,
  required Duration? playerDuration,
  required String durationLabel,
}) {
  final timelineTotal = timeline.totalDurationSec;
  if (timelineTotal > 0) {
    return timelineTotal;
  }
  return resolveLessonMediaDurationSec(
    playerDuration: playerDuration,
    mediaDurationSec: 0,
    durationLabel: durationLabel,
  );
}
