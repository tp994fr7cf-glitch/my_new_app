import 'package:cloud_firestore/cloud_firestore.dart';

int parseIntField(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? fallback;
  }
  return fallback;
}

double parseDoubleField(Object? value, {double fallback = 0}) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim()) ?? fallback;
  }
  return fallback;
}

double? parseNullableDoubleField(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}

String parseStringField(Object? value, {String fallback = ''}) {
  if (value is String) {
    return value;
  }
  if (value == null) {
    return fallback;
  }
  return value.toString();
}

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
