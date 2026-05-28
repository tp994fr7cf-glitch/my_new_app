import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/watched_range.dart';

void main() {
  group('watched ranges', () {
    test('merges overlapping and adjacent ranges', () {
      final ranges = mergeWatchedRanges(const [
        WatchedRange(startSec: 10, endSec: 20),
        WatchedRange(startSec: 0, endSec: 5),
        WatchedRange(startSec: 5, endSec: 11),
      ]);

      expect(ranges, hasLength(1));
      expect(ranges.first.startSec, 0);
      expect(ranges.first.endSec, 20);
    });

    test('sums separated ranges without filling gaps', () {
      final ranges = const [
        WatchedRange(startSec: 0, endSec: 10),
        WatchedRange(startSec: 30, endSec: 35),
      ];

      expect(sumWatchedSeconds(ranges), 15);
      expect(maxWatchedPositionSec(ranges), 35);
    });

    test('converts legacy watchedSecondIndexes to ranges', () {
      final ranges = watchedIndexesToRanges([0, 1, 2, 5, 6, 10, 10]);

      expect(ranges, hasLength(3));
      expect(ranges[0].startSec, 0);
      expect(ranges[0].endSec, 3);
      expect(ranges[1].startSec, 5);
      expect(ranges[1].endSec, 7);
      expect(ranges[2].startSec, 10);
      expect(ranges[2].endSec, 11);
    });

    test('adds only the played second after seeking', () {
      final ranges = addWatchedRange(const [], startSec: 30, endSec: 31);

      expect(sumWatchedSeconds(ranges), 1);
      expect(ranges.single.startSec, 30);
      expect(ranges.single.endSec, 31);
    });
  });
}
