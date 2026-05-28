class WatchedRange {
  const WatchedRange({required this.startSec, required this.endSec});

  final int startSec;
  final int endSec;

  int get durationSec => endSec - startSec;

  Map<String, int> toFirestore() => {'startSec': startSec, 'endSec': endSec};
}

List<WatchedRange> addWatchedRange(
  List<WatchedRange> ranges, {
  required int startSec,
  required int endSec,
}) {
  if (endSec <= startSec) {
    return mergeWatchedRanges(ranges);
  }

  return mergeWatchedRanges([
    ...ranges,
    WatchedRange(startSec: startSec, endSec: endSec),
  ]);
}

List<WatchedRange> mergeWatchedRanges(List<WatchedRange> ranges) {
  final normalized =
      ranges.where((range) => range.endSec > range.startSec).toList()
        ..sort((a, b) {
          final startCompare = a.startSec.compareTo(b.startSec);
          if (startCompare != 0) {
            return startCompare;
          }
          return a.endSec.compareTo(b.endSec);
        });

  final merged = <WatchedRange>[];
  for (final range in normalized) {
    if (merged.isEmpty) {
      merged.add(range);
      continue;
    }

    final previous = merged.last;
    if (range.startSec <= previous.endSec) {
      merged[merged.length - 1] = WatchedRange(
        startSec: previous.startSec,
        endSec: range.endSec > previous.endSec ? range.endSec : previous.endSec,
      );
    } else {
      merged.add(range);
    }
  }

  return merged;
}

int sumWatchedSeconds(List<WatchedRange> ranges) {
  return mergeWatchedRanges(
    ranges,
  ).fold(0, (total, range) => total + range.durationSec);
}

int watchedSecondsAddedByRange(
  List<WatchedRange> ranges, {
  required int startSec,
  required int endSec,
}) {
  final beforeSeconds = sumWatchedSeconds(ranges);
  final afterSeconds = sumWatchedSeconds(
    addWatchedRange(ranges, startSec: startSec, endSec: endSec),
  );
  return afterSeconds - beforeSeconds;
}

int maxWatchedPositionSec(List<WatchedRange> ranges) {
  final merged = mergeWatchedRanges(ranges);
  if (merged.isEmpty) {
    return 0;
  }

  return merged.map((range) => range.endSec).reduce((a, b) => a > b ? a : b);
}

List<WatchedRange> watchedIndexesToRanges(Iterable<int> indexes) {
  final sorted = indexes.where((index) => index >= 0).toSet().toList()..sort();
  if (sorted.isEmpty) {
    return const [];
  }

  final ranges = <WatchedRange>[];
  var start = sorted.first;
  var previous = sorted.first;
  for (final index in sorted.skip(1)) {
    if (index == previous + 1) {
      previous = index;
      continue;
    }

    ranges.add(WatchedRange(startSec: start, endSec: previous + 1));
    start = index;
    previous = index;
  }
  ranges.add(WatchedRange(startSec: start, endSec: previous + 1));
  return ranges;
}

List<WatchedRange> watchedRangesFromFirestore(Object? value) {
  if (value is! List) {
    return const [];
  }

  final ranges = <WatchedRange>[];
  for (final item in value) {
    if (item is! Map) {
      continue;
    }

    final startSec = item['startSec'];
    final endSec = item['endSec'];
    if (startSec is! num || endSec is! num) {
      continue;
    }

    ranges.add(
      WatchedRange(startSec: startSec.toInt(), endSec: endSec.toInt()),
    );
  }

  return mergeWatchedRanges(ranges);
}

List<Map<String, int>> watchedRangesToFirestore(List<WatchedRange> ranges) {
  return mergeWatchedRanges(
    ranges,
  ).map((range) => range.toFirestore()).toList();
}
