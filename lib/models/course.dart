import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../utils/firestore_parsing.dart';
import 'lesson_media_segment.dart';
import 'lesson_media_timeline.dart';
import 'lesson_timed_anchor.dart';
import 'lesson_whiteboard.dart';

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

  static Course? tryFromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
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
    this.whiteboardLayers = const [],
    this.whiteboardDraftLayers = const [],
  });

  final String title;
  final String duration;
  final List<LessonMediaSegment> mediaSegments;
  final bool isPreview;
  final List<LessonWhiteboardLayer> whiteboardLayers;
  final List<LessonWhiteboardLayer> whiteboardDraftLayers;

  LessonMediaTimeline get mediaTimeline => LessonMediaTimeline(segments: mediaSegments);

  bool get hasMedia => lessonHasMediaSegments(mediaSegments);

  int get totalMediaDurationSec => mediaTimeline.totalDurationSec;

  LessonWhiteboardLayerBundle get publishedWhiteboardBundle =>
      LessonWhiteboardLayerBundle(layers: whiteboardLayers);

  LessonWhiteboardLayerBundle get draftWhiteboardBundle =>
      LessonWhiteboardLayerBundle(layers: whiteboardDraftLayers);

  LessonWhiteboard? get whiteboard => publishedWhiteboardBundle.toLegacyWhiteboard();

  LessonWhiteboard? get whiteboardDraft => draftWhiteboardBundle.toLegacyWhiteboard();

  bool get hasPublishedWhiteboard =>
      whiteboard != null && !whiteboard!.isEmpty;

  bool get hasAudioSegment => mediaSegments.any((segment) => segment.isAudio && segment.hasUrl);

  factory CourseLesson.fromMap(Map data) {
    final segmentsData = data['mediaSegments'];
    final whiteboardLayersData = data['whiteboardLayers'];
    final whiteboardDraftLayersData = data['whiteboardDraftLayers'];
    final legacyWhiteboardData = data['whiteboard'];
    final legacyWhiteboardDraftData = data['whiteboardDraft'];

    final parsedSegments = segmentsData is List
        ? segmentsData
              .whereType<Map>()
              .map(_tryParseMediaSegment)
              .whereType<LessonMediaSegment>()
              .toList()
        : const <LessonMediaSegment>[];

    final normalizedSegments = parsedSegments.isNotEmpty
        ? LessonMediaSegment.normalizeOrders(parsedSegments)
        : _legacySegmentsFromMap(data);

    var parsedPublishedLayers = whiteboardLayersData is List
        ? whiteboardLayersData
              .whereType<Map>()
              .map(_tryParseWhiteboardLayer)
              .whereType<LessonWhiteboardLayer>()
              .toList()
        : const <LessonWhiteboardLayer>[];
    if (parsedPublishedLayers.isEmpty && legacyWhiteboardData is Map) {
      parsedPublishedLayers =
          LessonWhiteboardLayerBundle.fromLegacyWhiteboard(
            LessonWhiteboard.fromMap(legacyWhiteboardData),
          ).layers;
    }

    var parsedDraftLayers = whiteboardDraftLayersData is List
        ? whiteboardDraftLayersData
              .whereType<Map>()
              .map(_tryParseWhiteboardLayer)
              .whereType<LessonWhiteboardLayer>()
              .toList()
        : const <LessonWhiteboardLayer>[];
    if (parsedDraftLayers.isEmpty && legacyWhiteboardDraftData is Map) {
      parsedDraftLayers = LessonWhiteboardLayerBundle.fromLegacyWhiteboard(
        LessonWhiteboard.fromMap(legacyWhiteboardDraftData),
      ).layers;
    }

    return CourseLesson(
      title: data['title'] as String? ?? '',
      duration: data['duration'] as String? ?? '',
      mediaSegments: normalizedSegments,
      isPreview: data['isPreview'] as bool? ?? false,
      whiteboardLayers: parsedPublishedLayers,
      whiteboardDraftLayers: parsedDraftLayers,
    );
  }

  static List<LessonMediaSegment> _legacySegmentsFromMap(Map data) {
    final legacyUrl = data['mediaUrl'] as String? ?? '';
    if (legacyUrl.trim().isEmpty) {
      return const [];
    }
    return [
      LessonMediaSegment(
        id: LessonMediaSegment.generateId(),
        order: 0,
        mediaType: data['mediaType'] as String? ?? 'video',
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

  Map<String, dynamic> toMap() {
    final normalizedSegments = LessonMediaSegment.normalizeOrders(mediaSegments);
    final publishedLayerMaps =
        LessonWhiteboardLayerBundle(layers: whiteboardLayers).toMapList();
    final draftLayerMaps =
        LessonWhiteboardLayerBundle(layers: whiteboardDraftLayers).toMapList();

    return {
      'title': title,
      'duration': duration,
      'mediaSegments': normalizedSegments.map((segment) => segment.toMap()).toList(),
      'isPreview': isPreview,
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
    bool clearWhiteboardLayers = false,
    bool clearWhiteboardDraftLayers = false,
  }) {
    return CourseLesson(
      title: title ?? this.title,
      duration: duration ?? this.duration,
      mediaSegments: mediaSegments ?? this.mediaSegments,
      isPreview: isPreview ?? this.isPreview,
      whiteboardLayers: clearWhiteboardLayers
          ? const []
          : (whiteboardLayers ?? this.whiteboardLayers),
      whiteboardDraftLayers: clearWhiteboardDraftLayers
          ? const []
          : (whiteboardDraftLayers ?? this.whiteboardDraftLayers),
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
  });

  final String id;
  final int lessonNumber;
  final int timestampSec;
  final String type;
  final LessonQuiz? quiz;
  final LessonTimedAnchorType anchorType;
  final String? segmentId;
  final int? globalTimestampSec;

  bool get isQuiz => type == 'quiz' && quiz != null;

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
      anchorType: LessonTimedAnchorType.fromStorage(data['anchorType'] as String?),
      segmentId: data['segmentId'] as String?,
      globalTimestampSec: data['globalTimestampSec'] == null
          ? null
          : parseIntField(data['globalTimestampSec']),
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
    );
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
        mediaSegments: const [
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
        mediaSegments: const [
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
        mediaSegments: const [
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
        mediaSegments: const [
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
