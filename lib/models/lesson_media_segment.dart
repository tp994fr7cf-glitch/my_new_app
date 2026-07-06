import 'dart:math';

class LessonMediaSegment {
  const LessonMediaSegment({
    required this.id,
    required this.order,
    this.title = '',
    this.mediaType = 'video',
    this.url = '',
    this.durationSec = 0,
  });

  final String id;
  final int order;
  final String title;
  final String mediaType;
  final String url;
  final int durationSec;

  bool get hasUrl => url.trim().isNotEmpty;
  bool get isAudio => mediaType == 'audio';
  bool get isVideo => !isAudio;

  factory LessonMediaSegment.fromMap(Map data) {
    return LessonMediaSegment(
      id: data['id'] as String? ?? '',
      order: (data['order'] as num?)?.toInt() ?? 0,
      title: data['title'] as String? ?? '',
      mediaType: data['mediaType'] as String? ?? 'video',
      url: data['url'] as String? ?? '',
      durationSec: (data['durationSec'] as num?)?.toInt() ?? 0,
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
    };
  }

  LessonMediaSegment copyWith({
    String? id,
    int? order,
    String? title,
    String? mediaType,
    String? url,
    int? durationSec,
  }) {
    return LessonMediaSegment(
      id: id ?? this.id,
      order: order ?? this.order,
      title: title ?? this.title,
      mediaType: mediaType ?? this.mediaType,
      url: url ?? this.url,
      durationSec: durationSec ?? this.durationSec,
    );
  }

  static String generateId() {
    final randomSuffix = Random().nextInt(1 << 32).toRadixString(16);
    return 'seg_${DateTime.now().microsecondsSinceEpoch}_$randomSuffix';
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
