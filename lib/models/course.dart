import 'package:cloud_firestore/cloud_firestore.dart';

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
      lessonCount: (data['lessonCount'] as num?)?.toInt() ?? 0,
      rating: (data['rating'] as num?)?.toDouble() ?? 0,
      priceLabel: data['priceLabel'] as String? ?? '',
      description: data['description'] as String? ?? '',
      lessons: lessonsData is List
          ? lessonsData
                .whereType<Map>()
                .map((lessonData) => CourseLesson.fromMap(lessonData))
                .toList()
          : const [],
      lessonEvents: lessonEventsData is List
          ? lessonEventsData
                .whereType<Map>()
                .map((eventData) => LessonEvent.fromMap(eventData))
                .toList()
          : const [],
    );
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
    this.mediaType = 'video',
    this.mediaUrl = '',
    this.isPreview = false,
  });

  final String title;
  final String duration;
  final String mediaType;
  final String mediaUrl;
  final bool isPreview;

  factory CourseLesson.fromMap(Map data) {
    return CourseLesson(
      title: data['title'] as String? ?? '',
      duration: data['duration'] as String? ?? '',
      mediaType: data['mediaType'] as String? ?? 'video',
      mediaUrl: data['mediaUrl'] as String? ?? '',
      isPreview: data['isPreview'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'duration': duration,
      'mediaType': mediaType,
      'mediaUrl': mediaUrl,
      'isPreview': isPreview,
    };
  }
}

class LessonEvent {
  const LessonEvent({
    required this.id,
    required this.lessonNumber,
    required this.timestampSec,
    required this.type,
    this.quiz,
  });

  final String id;
  final int lessonNumber;
  final int timestampSec;
  final String type;
  final LessonQuiz? quiz;

  bool get isQuiz => type == 'quiz' && quiz != null;

  factory LessonEvent.fromMap(Map data) {
    final quizData = data['quiz'];

    return LessonEvent(
      id: data['id'] as String? ?? '',
      lessonNumber: (data['lessonNumber'] as num?)?.toInt() ?? 1,
      timestampSec: (data['timestampSec'] as num?)?.toInt() ?? 0,
      type: data['type'] as String? ?? 'quiz',
      quiz: quizData is Map ? LessonQuiz.fromMap(quizData) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'lessonNumber': lessonNumber,
      'timestampSec': timestampSec,
      'type': type,
      if (quiz != null) 'quiz': quiz!.toMap(),
    };
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
      correctChoiceIndex: (data['correctChoiceIndex'] as num?)?.toInt() ?? 0,
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
        mediaType: 'audio',
        isPreview: true,
      ),
      CourseLesson(title: '頻出表現の聞き分け', duration: '1分30秒', mediaType: 'audio'),
      CourseLesson(title: 'ニュース音声に慣れる', duration: '1分30秒', mediaType: 'audio'),
      CourseLesson(title: 'シャドーイング実践', duration: '1分30秒', mediaType: 'audio'),
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
