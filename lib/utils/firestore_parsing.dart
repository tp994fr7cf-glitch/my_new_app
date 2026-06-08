import 'package:cloud_firestore/cloud_firestore.dart';

List<String> parseStringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.whereType<String>().toList();
}

DateTime timestampOrEpoch(Timestamp? timestamp) {
  return timestamp?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
}

Timestamp? postedTimestamp(Timestamp? createdAt, Timestamp? updatedAt) {
  return createdAt ?? updatedAt;
}

Timestamp? editedTimestamp(Timestamp? createdAt, Timestamp? updatedAt) {
  return updatedAt ?? createdAt;
}

int compareTimestampDescWithUnknownLast(Timestamp? a, Timestamp? b) {
  if (a == null && b == null) {
    return 0;
  }
  if (a == null) {
    return 1;
  }
  if (b == null) {
    return -1;
  }
  return b.toDate().compareTo(a.toDate());
}

List<T> sortByUpdatedAt<T>(
  List<T> items,
  Timestamp? Function(T item) updatedAt,
) {
  return [...items]..sort((a, b) {
    final bUpdatedAt = timestampOrEpoch(updatedAt(b));
    final aUpdatedAt = timestampOrEpoch(updatedAt(a));
    return bUpdatedAt.compareTo(aUpdatedAt);
  });
}
