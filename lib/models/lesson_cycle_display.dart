class LessonCycleDisplayRecord {
  const LessonCycleDisplayRecord({
    required this.cycleNumber,
    required this.isDeleted,
  });

  final int cycleNumber;
  final bool isDeleted;
}

int displayedCycleNumber({
  required int actualCycleNumber,
  required Iterable<LessonCycleDisplayRecord> records,
}) {
  final recordsByCycle = <int, List<LessonCycleDisplayRecord>>{};
  for (final record in records) {
    recordsByCycle.putIfAbsent(record.cycleNumber, () => []).add(record);
  }

  final fullyDeletedCycleCount = recordsByCycle.entries
      .where((entry) => entry.value.every((record) => record.isDeleted))
      .where((entry) => entry.key < actualCycleNumber)
      .length;

  return actualCycleNumber - fullyDeletedCycleCount;
}
