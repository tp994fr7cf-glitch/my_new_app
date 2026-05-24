import 'package:flutter/material.dart';

import '../models/course.dart';
import 'course_detail_page.dart';

class CourseListPage extends StatelessWidget {
  const CourseListPage({super.key});

  static const _courses = [
    Course(
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
          duration: '12分',
          isPreview: true,
        ),
        CourseLesson(title: 'Dartの基本文法', duration: '18分'),
        CourseLesson(title: '画面レイアウトの作り方', duration: '22分'),
        CourseLesson(title: 'ボタン操作と状態管理の基礎', duration: '20分'),
      ],
    ),
    Course(
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
        CourseLesson(title: '数と式の復習', duration: '16分', isPreview: true),
        CourseLesson(title: '因数分解の考え方', duration: '19分'),
        CourseLesson(title: '二次関数のグラフ', duration: '24分'),
        CourseLesson(title: '図形と計量の基本', duration: '21分'),
      ],
    ),
    Course(
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
        CourseLesson(title: '短い会話を聞き取るコツ', duration: '10分', isPreview: true),
        CourseLesson(title: '頻出表現の聞き分け', duration: '17分'),
        CourseLesson(title: 'ニュース音声に慣れる', duration: '23分'),
        CourseLesson(title: 'シャドーイング実践', duration: '15分'),
      ],
    ),
    Course(
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
        CourseLesson(title: '社会人としての基本姿勢', duration: '11分', isPreview: true),
        CourseLesson(title: '報連相の実践', duration: '14分'),
        CourseLesson(title: 'ビジネスメールの基礎', duration: '18分'),
        CourseLesson(title: '会議参加のマナー', duration: '13分'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('講座一覧')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              '学びたい講座を探す',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('今は仮データです。後でFirestoreの講座データから表示する形に変更します。'),
            const SizedBox(height: 16),
            const TextField(
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
                labelText: '講座名・先生名・カテゴリで検索',
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                Chip(label: Text('すべて')),
                Chip(label: Text('プログラミング')),
                Chip(label: Text('数学')),
                Chip(label: Text('英語')),
                Chip(label: Text('企業研修')),
              ],
            ),
            const SizedBox(height: 24),
            for (final course in _courses) ...[
              _CourseCard(course: course),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course});

  final Course course;

  void _openCourseDetail(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => CourseDetailPage(course: course)));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _openCourseDetail(context);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.ondemand_video,
                  size: 48,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(course.category)),
                  Chip(label: Text(course.level)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                course.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text('講師: ${course.instructorName}'),
              const SizedBox(height: 8),
              Text(course.description),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.star, size: 18),
                  const SizedBox(width: 4),
                  Text(course.rating.toStringAsFixed(1)),
                  const SizedBox(width: 16),
                  const Icon(Icons.schedule, size: 18),
                  const SizedBox(width: 4),
                  Text(course.duration),
                  const SizedBox(width: 16),
                  const Icon(Icons.list_alt, size: 18),
                  const SizedBox(width: 4),
                  Text('${course.lessonCount}本'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    course.priceLabel,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      _openCourseDetail(context);
                    },
                    child: const Text('詳細を見る'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
