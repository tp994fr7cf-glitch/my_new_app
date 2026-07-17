import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../utils/firestore_parsing.dart';
import 'lesson_media_segment.dart';
import 'lesson_media_timeline.dart';
import 'lesson_playback_mode.dart';
import 'lesson_timed_anchor.dart';
import 'lesson_whiteboard.dart';
import 'lesson_whiteboard_board_set.dart';

class Course {
  const Course({
    this.id,
    this.courseCode,
    required this.title,
    required this.instructorName,
    required this.category,
    required this.level,
    required this.duration,
    required this.lessonCount,
    required this.rating,
    required this.priceLabel,
    required this.description,
    required this.lessons,
    this.lessonEvents = const [],
    this.instructorId,
  });

  final String? id;
  final String? courseCode;
  final String? instructorId;
  final String title;
  final String instructorName;
  final String category;
  final String level;
  final String duration;
  final int lessonCount;
  final double rating;
  final String priceLabel;
  final String description;
  final List<CourseLesson> lessons;
  final List<LessonEvent> lessonEvents;

  String get storageId => id ?? title.replaceAll('/', '_');

  factory Course.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Course.fromMap(doc.data() ?? {}, id: doc.id);
  }

  static Course? tryFromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      return Course.fromFirestore(doc);
    } catch (error, stackTrace) {
      debugPrint('Skip course ${doc.id}: $error\n$stackTrace');
      return null;
    }
  }

  factory Course.fromMap(Map data, {String? id}) {
    final lessonsData = data['lessons'];
    final lessonEventsData = data['lessonEvents'];

    return Course(
      id: id ?? data['id'] as String?,
      courseCode: data['courseCode'] as String?,
      instructorId: data['instructorId'] as String?,
      title: data['title'] as String? ?? '',
      instructorName: data['instructorName'] as String? ?? '',
      category: data['category'] as String? ?? '',
      level: data['level'] as String? ?? '',
      duration: data['duration'] as String? ?? '',
      lessonCount: parseIntField(data['lessonCount']),
      rating: parseDoubleField(data['rating']),
      priceLabel: parseStringField(data['priceLabel']),
      description: parseStringField(data['description']),
      lessons: lessonsData is List
          ? lessonsData
                .whereType<Map>()
                .map(_tryParseCourseLesson)
                .whereType<CourseLesson>()
                .toList()
          : const [],
      lessonEvents: lessonEventsData is List
          ? lessonEventsData
                .whereType<Map>()
                .map(_tryParseLessonEvent)
                .whereType<LessonEvent>()
                .toList()
          : const [],
    );
  }

  static CourseLesson? _tryParseCourseLesson(Map lessonData) {
    try {
      return CourseLesson.fromMap(lessonData);
    } catch (error, stackTrace) {
      debugPrint('Skip lesson in course data: $error\n$stackTrace');
      return null;
    }
  }

  static LessonEvent? _tryParseLessonEvent(Map eventData) {
    try {
      return LessonEvent.fromMap(eventData);
    } catch (error, stackTrace) {
      debugPrint('Skip lesson event in course data: $error\n$stackTrace');
      return null;
    }
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      if (courseCode != null) 'courseCode': courseCode,
      if (instructorId != null) 'instructorId': instructorId,
      'instructorName': instructorName,
      'category': category,
      'level': level,
      'duration': duration,
      'lessonCount': lessonCount,
      'rating': rating,
      'priceLabel': priceLabel,
      'description': description,
      'lessons': lessons.map((lesson) => lesson.toMap()).toList(),
      'lessonEvents': lessonEvents.map((event) => event.toMap()).toList(),
    };
  }
}

class CourseLesson {
  const CourseLesson({
    required this.title,
    required this.duration,
    this.mediaSegments = const [],
    this.isPreview = false,
    List<LessonWhiteboardLayer> whiteboardLayers = const [],
    List<LessonWhiteboardLayer> whiteboardDraftLayers = const [],
    this.playbackMode = LessonPlaybackMode.continuous,
    List<String>? publishedSegmentIds,
    this.contentRevision = 1,
    BoardSet? publishedBoardSet,
    BoardSet? draftBoardSet,
  }) : _legacyPublishedLayers = whiteboardLayers,
       _legacyDraftLayers = whiteboardDraftLayers,
       _publishedSegmentIds = publishedSegmentIds ?? const [],
       _hasExplicitPublishedSegmentIds = publishedSegmentIds != null,
       _publishedBoardSet = publishedBoardSet,
       _draftBoardSet = draftBoardSet;

  final String title;
  final String duration;
  final List<LessonMediaSegment> mediaSegments;
  final bool isPreview;
  final LessonPlaybackMode playbackMode;
  final List<String> _publishedSegmentIds;
  final int contentRevision;
  final List<LessonWhiteboardLayer> _legacyPublishedLayers;
  final List<LessonWhiteboardLayer> _legacyDraftLayers;
  final bool _hasExplicitPublishedSegmentIds;
  final BoardSet? _publishedBoardSet;
  final BoardSet? _draftBoardSet;

  List<String> get publishedSegmentIds {
    if (_hasExplicitPublishedSegmentIds) {
      return _publishedSegmentIds;
    }
    return LessonMediaSegment.normalizeOrders(
      mediaSegments,
    ).map((segment) => segment.id).toList();
  }

  Set<String> get lockedSegmentIds {
    return publishedSegmentIds.toSet();
  }

  List<LessonMediaSegment> get effectivePublishedMediaSegments {
    final lockedIds = lockedSegmentIds;
    return LessonMediaSegment.normalizeOrders(
      mediaSegments.where((segment) => lockedIds.contains(segment.id)).toList(),
    );
  }

  LessonMediaTimeline get mediaTimeline =>
      LessonMediaTimeline(segments: effectivePublishedMediaSegments);

  bool get hasMedia => lessonHasMediaSegments(effectivePublishedMediaSegments);

  int get totalMediaDurationSec => mediaTimeline.totalDurationSec;

  List<LessonWhiteboardLayer> get whiteboardLayers {
    final boardSet = _publishedBoardSet;
    if (boardSet != null) {
      return boardSet.defaultBoard?.layerBundle.layers ?? const [];
    }
    return _legacyPublishedLayers;
  }

  List<LessonWhiteboardLayer> get whiteboardDraftLayers {
    final boardSet = _draftBoardSet;
    if (boardSet != null) {
      return boardSet.defaultBoard?.layerBundle.layers ?? const [];
    }
    return _legacyDraftLayers;
  }

  BoardSet get publishedBoardSet {
    return _publishedBoardSet ??
        (_legacyPublishedLayers.isEmpty
            ? const BoardSet()
            : BoardSet.fromLegacyLayers(_legacyPublishedLayers));
  }

  BoardSet get draftBoardSet {
    return _draftBoardSet ??
        (_legacyDraftLayers.isEmpty
            ? const BoardSet()
            : BoardSet.fromLegacyLayers(_legacyDraftLayers));
  }

  BoardSet get publishedWhiteboardBoardSet => publishedBoardSet;

  BoardSet get draftWhiteboardBoardSet => draftBoardSet;

  LessonWhiteboardLayerBundle get publishedWhiteboardBundle {
    return publishedBoardSet.defaultBoard?.layerBundle ??
        const LessonWhiteboardLayerBundle();
  }

  LessonWhiteboardLayerBundle get draftWhiteboardBundle {
    return draftBoardSet.defaultBoard?.layerBundle ??
        const LessonWhiteboardLayerBundle();
  }

  LessonWhiteboard? get whiteboard =>
      publishedWhiteboardBundle.toLegacyWhiteboard();

  LessonWhiteboard? get whiteboardDraft =>
      draftWhiteboardBundle.toLegacyWhiteboard();

  bool get hasPublishedWhiteboard => whiteboard != null && !whiteboard!.isEmpty;

  bool get hasAudioSegment => effectivePublishedMediaSegments.any(
    (segment) => segment.isAudio && segment.hasUrl,
  );

  factory CourseLesson.fromMap(Map data) {
    final segmentsData = data['mediaSegments'];
    final publishedSegmentIdsData = data['publishedSegmentIds'];
    final whiteboardLayersData = data['whiteboardLayers'];
    final whiteboardDraftLayersData = data['whiteboardDraftLayers'];
    final legacyWhiteboardData = data['whiteboard'];
    final legacyWhiteboardDraftData = data['whiteboardDraft'];
    final publishedBoardSetData = data['publishedBoardSet'];
    final draftBoardSetData = data['draftBoardSet'];

    final parsedSegments = segmentsData is List
        ? segmentsData
              .whereType<Map>()
              .map(_tryParseMediaSegment)
              .whereType<LessonMediaSegment>()
              .toList()
        : const <LessonMediaSegment>[];

    final normalizedSegments = parsedSegments.isNotEmpty
        ? LessonMediaSegment.normalizeOrders(
            _repairBlankAndDuplicateSegmentIds(parsedSegments),
          )
        : _legacySegmentsFromMap(data);

    var parsedPublishedLayers = whiteboardLayersData is List
        ? whiteboardLayersData
              .whereType<Map>()
              .map(_tryParseWhiteboardLayer)
              .whereType<LessonWhiteboardLayer>()
              .toList()
        : const <LessonWhiteboardLayer>[];
    if (parsedPublishedLayers.isEmpty && legacyWhiteboardData is Map) {
      parsedPublishedLayers = _tryParseLegacyWhiteboardLayers(
        legacyWhiteboardData,
      );
    }

    var parsedDraftLayers = whiteboardDraftLayersData is List
        ? whiteboardDraftLayersData
              .whereType<Map>()
              .map(_tryParseWhiteboardLayer)
              .whereType<LessonWhiteboardLayer>()
              .toList()
        : const <LessonWhiteboardLayer>[];
    if (parsedDraftLayers.isEmpty && legacyWhiteboardDraftData is Map) {
      parsedDraftLayers = _tryParseLegacyWhiteboardLayers(
        legacyWhiteboardDraftData,
      );
    }

    final parsedContentRevision = parseIntField(
      data['contentRevision'],
      fallback: 1,
    );
    final segmentIds = normalizedSegments.map((segment) => segment.id).toSet();

    return CourseLesson(
      title: data['title'] is String ? data['title'] as String : '',
      duration: data['duration'] is String ? data['duration'] as String : '',
      mediaSegments: normalizedSegments,
      isPreview: data['isPreview'] is bool ? data['isPreview'] as bool : false,
      whiteboardLayers: parsedPublishedLayers,
      whiteboardDraftLayers: parsedDraftLayers,
      playbackMode: LessonPlaybackMode.fromStorage(
        data['playbackMode'] is String ? data['playbackMode'] as String : null,
      ),
      publishedSegmentIds: publishedSegmentIdsData is List
          ? _parsePublishedSegmentIds(
              publishedSegmentIdsData,
              validSegmentIds: segmentIds,
            )
          : null,
      contentRevision:
          parsedContentRevision < 1 || parsedContentRevision > 2147483647
          ? 1
          : parsedContentRevision,
      publishedBoardSet: publishedBoardSetData is Map
          ? BoardSet.fromMap(publishedBoardSetData)
          : null,
      draftBoardSet: draftBoardSetData is Map
          ? BoardSet.fromMap(draftBoardSetData)
          : null,
    );
  }

  static List<LessonMediaSegment> _legacySegmentsFromMap(Map data) {
    final legacyUrl = data['mediaUrl'] is String
        ? data['mediaUrl'] as String
        : '';
    if (legacyUrl.trim().isEmpty) {
      return const [];
    }
    return [
      LessonMediaSegment(
        id: LessonMediaSegment.deterministicLegacyId(
          url: legacyUrl,
          mediaType: data['mediaType'] is String
              ? data['mediaType'] as String
              : 'video',
        ),
        order: 0,
        mediaType: data['mediaType'] is String
            ? data['mediaType'] as String
            : 'video',
        url: legacyUrl,
        durationSec: parseIntField(data['mediaDurationSec']),
      ),
    ];
  }

  static LessonMediaSegment? _tryParseMediaSegment(Map data) {
    try {
      return LessonMediaSegment.fromMap(data);
    } catch (error, stackTrace) {
      debugPrint('Skip media segment: $error\n$stackTrace');
      return null;
    }
  }

  static LessonWhiteboardLayer? _tryParseWhiteboardLayer(Map data) {
    try {
      return LessonWhiteboardLayer.fromMap(data);
    } catch (error, stackTrace) {
      debugPrint('Skip whiteboard layer: $error\n$stackTrace');
      return null;
    }
  }

  static List<LessonMediaSegment> _repairBlankAndDuplicateSegmentIds(
    List<LessonMediaSegment> segments,
  ) {
    final usedIds = <String>{};
    return [
      for (final entry in segments.indexed)
        entry.$2.copyWith(
          id: _usableUniqueSegmentId(
            segment: entry.$2,
            index: entry.$1,
            usedIds: usedIds,
          ),
        ),
    ];
  }

  static String _usableUniqueSegmentId({
    required LessonMediaSegment segment,
    required int index,
    required Set<String> usedIds,
  }) {
    var candidate = segment.id;
    if (candidate.trim().isEmpty || usedIds.contains(candidate)) {
      final stableSuffix = LessonMediaSegment.deterministicLegacyId(
        url: '${segment.id}\u0000${segment.url}\u0000$index',
        mediaType: segment.mediaType,
      ).substring('legacy_'.length);
      candidate = 'recovered_${stableSuffix}_$index';
      var collision = 1;
      while (usedIds.contains(candidate)) {
        candidate = 'recovered_${stableSuffix}_${index}_$collision';
        collision++;
      }
    }
    usedIds.add(candidate);
    return candidate;
  }

  static List<String> _parsePublishedSegmentIds(
    List data, {
    required Set<String> validSegmentIds,
  }) {
    final seen = <String>{};
    return [
      for (final id in data.whereType<String>())
        if (id.trim().isNotEmpty &&
            validSegmentIds.contains(id) &&
            seen.add(id))
          id,
    ];
  }

  static List<LessonWhiteboardLayer> _tryParseLegacyWhiteboardLayers(Map data) {
    try {
      return LessonWhiteboardLayerBundle.fromLegacyWhiteboard(
        LessonWhiteboard.fromMap(data),
      ).layers;
    } on Object {
      return const [];
    }
  }

  Map<String, dynamic> toMap() {
    final normalizedSegments = LessonMediaSegment.normalizeOrders(
      mediaSegments,
    );
    final publishedLayerMaps = publishedWhiteboardBundle.toMapList();
    final draftLayerMaps = draftWhiteboardBundle.toMapList();

    return {
      'title': title,
      'duration': duration,
      'mediaSegments': normalizedSegments
          .map((segment) => segment.toMap())
          .toList(),
      'isPreview': isPreview,
      'playbackMode': playbackMode.toStorage(),
      'publishedSegmentIds': _hasExplicitPublishedSegmentIds
          ? _publishedSegmentIds
          : normalizedSegments.map((segment) => segment.id).toList(),
      'contentRevision': contentRevision,
      'publishedBoardSet': publishedBoardSet.toMap(),
      'draftBoardSet': draftBoardSet.toMap(),
      if (publishedLayerMaps.isNotEmpty) 'whiteboardLayers': publishedLayerMaps,
      if (draftLayerMaps.isNotEmpty) 'whiteboardDraftLayers': draftLayerMaps,
    };
  }

  CourseLesson copyWith({
    String? title,
    String? duration,
    List<LessonMediaSegment>? mediaSegments,
    bool? isPreview,
    List<LessonWhiteboardLayer>? whiteboardLayers,
    List<LessonWhiteboardLayer>? whiteboardDraftLayers,
    LessonPlaybackMode? playbackMode,
    List<String>? publishedSegmentIds,
    int? contentRevision,
    BoardSet? publishedBoardSet,
    BoardSet? draftBoardSet,
    bool clearWhiteboardLayers = false,
    bool clearWhiteboardDraftLayers = false,
    bool clearPublishedBoardSet = false,
    bool clearDraftBoardSet = false,
  }) {
    final nextPublishedLayers = clearWhiteboardLayers
        ? const <LessonWhiteboardLayer>[]
        : (whiteboardLayers ?? this.whiteboardLayers);
    final nextDraftLayers = clearWhiteboardDraftLayers
        ? const <LessonWhiteboardLayer>[]
        : (whiteboardDraftLayers ?? this.whiteboardDraftLayers);

    var nextPublishedBoardSet = clearPublishedBoardSet
        ? const BoardSet()
        : (publishedBoardSet ?? _publishedBoardSet);
    if (publishedBoardSet == null &&
        !clearPublishedBoardSet &&
        _publishedBoardSet != null &&
        (whiteboardLayers != null || clearWhiteboardLayers)) {
      nextPublishedBoardSet = _publishedBoardSet.copyWithDefaultLayerBundle(
        LessonWhiteboardLayerBundle(layers: nextPublishedLayers),
      );
    }

    var nextDraftBoardSet = clearDraftBoardSet
        ? const BoardSet()
        : (draftBoardSet ?? _draftBoardSet);
    if (draftBoardSet == null &&
        !clearDraftBoardSet &&
        _draftBoardSet != null &&
        (whiteboardDraftLayers != null || clearWhiteboardDraftLayers)) {
      nextDraftBoardSet = _draftBoardSet.copyWithDefaultLayerBundle(
        LessonWhiteboardLayerBundle(layers: nextDraftLayers),
      );
    }

    return CourseLesson(
      title: title ?? this.title,
      duration: duration ?? this.duration,
      mediaSegments: mediaSegments ?? this.mediaSegments,
      isPreview: isPreview ?? this.isPreview,
      whiteboardLayers: nextPublishedLayers,
      whiteboardDraftLayers: nextDraftLayers,
      playbackMode: playbackMode ?? this.playbackMode,
      publishedSegmentIds:
          publishedSegmentIds ??
          (_hasExplicitPublishedSegmentIds
              ? this.publishedSegmentIds
              : (mediaSegments == null ? null : lockedSegmentIds.toList())),
      contentRevision: contentRevision ?? this.contentRevision,
      publishedBoardSet: nextPublishedBoardSet,
      draftBoardSet: nextDraftBoardSet,
    );
  }
}

class LessonEvent {
  const LessonEvent({
    required this.id,
    required this.lessonNumber,
    required this.timestampSec,
    required this.type,
    this.quiz,
    this.anchorType = LessonTimedAnchorType.global,
    this.segmentId,
    this.globalTimestampSec,
    this.quizVersion = 1,
  });

  final String id;
  final int lessonNumber;
  final int timestampSec;
  final String type;
  final LessonQuiz? quiz;
  final LessonTimedAnchorType anchorType;
  final String? segmentId;
  final int? globalTimestampSec;
  final int quizVersion;

  bool get isQuiz => type == 'quiz' && quiz != null;
  String get quizAnswerKey => quizVersion > 1 ? '$id:v$quizVersion' : id;

  LessonTimedAnchor get timedAnchor => LessonTimedAnchor(
    anchorType: anchorType,
    timestampSec: timestampSec,
    segmentId: segmentId,
    globalTimestampSec: globalTimestampSec,
  );

  int resolveGlobalTimestampSec(LessonMediaTimeline timeline) {
    return timedAnchor.resolveGlobalTimestampSec(timeline);
  }

  factory LessonEvent.fromMap(Map data) {
    final quizData = data['quiz'];

    return LessonEvent(
      id: data['id'] as String? ?? '',
      lessonNumber: parseIntField(data['lessonNumber'], fallback: 1),
      timestampSec: parseIntField(data['timestampSec']),
      type: data['type'] as String? ?? 'quiz',
      quiz: quizData is Map ? LessonQuiz.fromMap(quizData) : null,
      anchorType: LessonTimedAnchorType.fromStorage(
        data['anchorType'] is String ? data['anchorType'] as String : null,
      ),
      segmentId: data['segmentId'] is String
          ? data['segmentId'] as String
          : null,
      globalTimestampSec: _parseNullableInt(data['globalTimestampSec']),
      quizVersion: _parseQuizVersion(data['quizVersion']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'lessonNumber': lessonNumber,
      'timestampSec': timestampSec,
      'type': type,
      if (quiz != null) 'quiz': quiz!.toMap(),
      if (anchorType != LessonTimedAnchorType.global)
        'anchorType': anchorType.toStorage(),
      if (segmentId != null && segmentId!.isNotEmpty) 'segmentId': segmentId,
      if (globalTimestampSec != null) 'globalTimestampSec': globalTimestampSec,
      'quizVersion': quizVersion,
    };
  }

  LessonEvent withResolvedGlobalTimestamp(LessonMediaTimeline timeline) {
    return LessonEvent(
      id: id,
      lessonNumber: lessonNumber,
      timestampSec: timestampSec,
      type: type,
      quiz: quiz,
      anchorType: anchorType,
      segmentId: segmentId,
      globalTimestampSec: resolveGlobalTimestampSec(timeline),
      quizVersion: quizVersion,
    );
  }

  static int _parseQuizVersion(Object? value) {
    final parsed = parseIntField(value, fallback: 1);
    return parsed < 1 || parsed > 2147483647 ? 1 : parsed;
  }

  static int? _parseNullableInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      if (!value.toDouble().isFinite) {
        return null;
      }
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }
}

class LessonQuiz {
  const LessonQuiz({
    required this.question,
    required this.choices,
    required this.correctChoiceIndex,
    this.explanation = '',
  });

  final String question;
  final List<String> choices;
  final int correctChoiceIndex;
  final String explanation;

  factory LessonQuiz.fromMap(Map data) {
    final choicesData = data['choices'];

    return LessonQuiz(
      question: data['question'] as String? ?? '',
      choices: choicesData is List
          ? choicesData.whereType<String>().toList()
          : const [],
      correctChoiceIndex: parseIntField(data['correctChoiceIndex']),
      explanation: data['explanation'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'question': question,
      'choices': choices,
      'correctChoiceIndex': correctChoiceIndex,
      'explanation': explanation,
    };
  }
}

const sampleCourses = [
  Course(
    id: 'sample-flutter-introduction',
    title: 'Flutter入門: はじめてのスマホアプリ開発',
    instructorName: '山田 太郎',
    category: 'プログラミング',
    level: '初心者向け',
    duration: '6時間',
    lessonCount: 24,
    rating: 4.7,
    priceLabel: '無料',
    description: 'FlutterとDartの基礎を学び、簡単なアプリ画面を作れるようになる講座です。',
    lessons: [
      CourseLesson(
        title: 'Flutterで作るアプリの全体像',
        duration: '1分30秒',
        isPreview: true,
      ),
      CourseLesson(title: 'Dartの基本文法', duration: '1分30秒'),
      CourseLesson(title: '画面レイアウトの作り方', duration: '1分30秒'),
      CourseLesson(title: 'ボタン操作と状態管理の基礎', duration: '1分30秒'),
    ],
    lessonEvents: [
      LessonEvent(
        id: 'sample-flutter-quiz-1',
        lessonNumber: 1,
        timestampSec: 0,
        type: 'quiz',
        quiz: LessonQuiz(
          question: 'Flutterで画面を作るときの基本単位はどれですか？',
          choices: ['Widget', 'Database', 'Server'],
          correctChoiceIndex: 0,
          explanation: 'FlutterではWidgetを組み合わせて画面を作ります。',
        ),
      ),
    ],
  ),
  Course(
    id: 'sample-high-school-math',
    title: '高校数学I 基礎から復習',
    instructorName: '佐藤 花子',
    category: '数学',
    level: '基礎',
    duration: '8時間',
    lessonCount: 32,
    rating: 4.5,
    priceLabel: '¥1,200',
    description: '数と式、二次関数、図形と計量を基礎から丁寧に復習します。',
    lessons: [
      CourseLesson(title: '数と式の復習', duration: '1分30秒', isPreview: true),
      CourseLesson(title: '因数分解の考え方', duration: '1分30秒'),
      CourseLesson(title: '二次関数のグラフ', duration: '1分30秒'),
      CourseLesson(title: '図形と計量の基本', duration: '1分30秒'),
    ],
  ),
  Course(
    id: 'sample-english-listening',
    title: '英語リスニング集中トレーニング',
    instructorName: 'English Lab',
    category: '英語',
    level: '中級',
    duration: '4時間',
    lessonCount: 18,
    rating: 4.6,
    priceLabel: 'サブスク対象',
    description: '短い会話からニュース音声まで、段階的に聞き取る力を伸ばします。',
    lessons: [
      CourseLesson(
        title: '短い会話を聞き取るコツ',
        duration: '1分30秒',
        mediaSegments: [
          LessonMediaSegment(
            id: 'sample-audio-1',
            order: 0,
            mediaType: 'audio',
          ),
        ],
        isPreview: true,
      ),
      CourseLesson(
        title: '頻出表現の聞き分け',
        duration: '1分30秒',
        mediaSegments: [
          LessonMediaSegment(
            id: 'sample-audio-2',
            order: 0,
            mediaType: 'audio',
          ),
        ],
      ),
      CourseLesson(
        title: 'ニュース音声に慣れる',
        duration: '1分30秒',
        mediaSegments: [
          LessonMediaSegment(
            id: 'sample-audio-3',
            order: 0,
            mediaType: 'audio',
          ),
        ],
      ),
      CourseLesson(
        title: 'シャドーイング実践',
        duration: '1分30秒',
        mediaSegments: [
          LessonMediaSegment(
            id: 'sample-audio-4',
            order: 0,
            mediaType: 'audio',
          ),
        ],
      ),
    ],
  ),
  Course(
    id: 'sample-business-manner',
    title: '企業研修: 新入社員のためのビジネスマナー',
    instructorName: '研修サポート株式会社',
    category: '企業研修',
    level: '初心者向け',
    duration: '3時間',
    lessonCount: 12,
    rating: 4.3,
    priceLabel: '組織向け',
    description: 'メール、報連相、会議参加など、社会人としての基本を学ぶ研修講座です。',
    lessons: [
      CourseLesson(title: '社会人としての基本姿勢', duration: '1分30秒', isPreview: true),
      CourseLesson(title: '報連相の実践', duration: '1分30秒'),
      CourseLesson(title: 'ビジネスメールの基礎', duration: '1分30秒'),
      CourseLesson(title: '会議参加のマナー', duration: '1分30秒'),
    ],
  ),
];
