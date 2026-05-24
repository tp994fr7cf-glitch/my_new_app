import 'package:flutter/material.dart';

import '../models/course.dart';

class CourseDetailPage extends StatelessWidget {
  const CourseDetailPage({super.key, required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('講座詳細')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.ondemand_video,
                size: 72,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(course.category)),
                Chip(label: Text(course.level)),
                Chip(label: Text(course.priceLabel)),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              course.title,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '講師: ${course.instructorName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.star, size: 20),
                const SizedBox(width: 4),
                Text(course.rating.toStringAsFixed(1)),
                const SizedBox(width: 16),
                const Icon(Icons.schedule, size: 20),
                const SizedBox(width: 4),
                Text(course.duration),
                const SizedBox(width: 16),
                const Icon(Icons.list_alt, size: 20),
                const SizedBox(width: 4),
                Text('${course.lessonCount}本'),
              ],
            ),
            const SizedBox(height: 24),
            const _SectionTitle('講座概要'),
            const SizedBox(height: 8),
            Text(course.description),
            const SizedBox(height: 24),
            const _SectionTitle('この講座で学べること'),
            const SizedBox(height: 8),
            const _BulletText('録画済み動画で自分のペースで学習できます。'),
            const _BulletText('基礎から順番に進められるレッスン構成です。'),
            const _BulletText('今後、コメントや学習記録と連携できる形に育てます。'),
            const SizedBox(height: 24),
            const _SectionTitle('レッスン一覧'),
            const SizedBox(height: 8),
            for (final entry in course.lessons.indexed)
              _LessonTile(index: entry.$1 + 1, lesson: entry.$2),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    const SnackBar(content: Text('動画視聴画面は次のステップで作ります。')),
                  );
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('受講を開始する'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
    );
  }
}

class _BulletText extends StatelessWidget {
  const _BulletText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('・'),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({required this.index, required this.lesson});

  final int index;
  final CourseLesson lesson;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('$index')),
        title: Text(lesson.title),
        subtitle: Text(lesson.duration),
        trailing: lesson.isPreview
            ? const Chip(label: Text('無料プレビュー'))
            : const Icon(Icons.lock_open),
      ),
    );
  }
}
