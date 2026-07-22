import 'dart:math';

import '../utils/firestore_parsing.dart';

class LessonMediaSegment {
  const LessonMediaSegment({
    required this.id,
    required this.order,
    this.title = '',
    this.mediaType = 'video',
    this.url = '',
    this.durationSec = 0,
    this.durationMs = 0,
  });

  final String id;
  final int order;
  final String title;
  final String mediaType;
  final String url;
  final int durationSec;
  final int durationMs;

  bool get hasUrl => url.trim().isNotEmpty;
  bool get isAudio => mediaType == 'audio';
  bool get isVideo => !isAudio;
  double get durationSecExact =>
      durationMs > 0 ? durationMs / 1000 : durationSec.toDouble();

  factory LessonMediaSegment.fromMap(Map data) {
    return LessonMediaSegment(
      id: parseStringField(data['id']),
      order: parseIntField(data['order']),
      title: parseStringField(data['title']),
      mediaType: parseStringField(data['mediaType'], fallback: 'video'),
      url: parseStringField(data['url']),
      durationSec: parseIntField(data['durationSec']),
      durationMs: parseIntField(data['durationMs']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'order': order,
      'title': title,
      'mediaType': mediaType,
      'url': url,
      if (durationSec > 0) 'durationSec': durationSec,
      if (durationMs > 0) 'durationMs': durationMs,
    };
  }

  LessonMediaSegment copyWith({
    String? id,
    int? order,
    String? title,
    String? mediaType,
    String? url,
    int? durationSec,
    int? durationMs,
  }) {
    return LessonMediaSegment(
      id: id ?? this.id,
      order: order ?? this.order,
      title: title ?? this.title,
      mediaType: mediaType ?? this.mediaType,
      url: url ?? this.url,
      durationSec: durationSec ?? this.durationSec,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  static String generateId() {
    final randomSuffix = Random().nextInt(1 << 32).toRadixString(16);
    return 'seg_${DateTime.now().microsecondsSinceEpoch}_$randomSuffix';
  }

  static String deterministicLegacyId({
    required String url,
    required String mediaType,
  }) {
    var hash = 0;
    for (final codeUnit in '$mediaType\u0000$url'.codeUnits) {
      hash = ((hash << 5) - hash + codeUnit) & 0xffffffff;
    }
    return 'legacy_${hash.toRadixString(16).padLeft(8, '0')}';
  }

  static List<LessonMediaSegment> normalizeOrders(
    List<LessonMediaSegment> segments,
  ) {
    final sorted = List<LessonMediaSegment>.from(segments)
      ..sort((a, b) => a.order.compareTo(b.order));
    return [
      for (var index = 0; index < sorted.length; index++)
        sorted[index].copyWith(order: index),
    ];
  }
}

bool lessonHasMediaSegments(List<LessonMediaSegment> segments) {
  return segments.any((segment) => segment.hasUrl);
}
