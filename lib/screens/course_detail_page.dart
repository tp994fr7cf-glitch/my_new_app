import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import 'teacher_interaction_manage_page.dart';
import 'teacher_lesson_manage_page.dart';
import 'video_lesson_page.dart';

class CourseDetailPage extends StatelessWidget {
  const CourseDetailPage({
    super.key,
    required this.course,
    this.isTeacherMode = false,
  });

  final Course course;
  final bool isTeacherMode;

  String get _courseId => course.storageId;

  Future<void> _saveLearningProgress({
    required CourseLesson lesson,
    required int lessonNumber,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final firestore = FirebaseFirestore.instance;
    final enrollmentRef = firestore
        .collection('users')
        .doc(user.uid)
        .collection('enrollments')
        .doc(_courseId);
    final eventRef = firestore
        .collection('users')
        .doc(user.uid)
        .collection('learningEvents')
        .doc();
    final now = FieldValue.serverTimestamp();
    final courseSnapshot = {'id': _courseId, ...course.toFirestore()};

    final batch = firestore.batch()
      ..set(enrollmentRef, {
        'userId': user.uid,
        'courseId': _courseId,
        'course': courseSnapshot,
        'lastLessonNumber': lessonNumber,
        'lastLessonTitle': lesson.title,
        'status': 'inProgress',
        'updatedAt': now,
        'createdAt': now,
      }, SetOptions(merge: true))
      ..set(eventRef, {
        'userId': user.uid,
        'type': 'lessonOpened',
        'courseId': _courseId,
        'courseTitle': course.title,
        'lessonNumber': lessonNumber,
        'lessonTitle': lesson.title,
        'createdAt': now,
      });

    await batch.commit();
  }

  Future<void> _openLesson(
    BuildContext context, {
    required CourseLesson lesson,
    required int lessonNumber,
  }) async {
    try {
      await _saveLearningProgress(lesson: lesson, lessonNumber: lessonNumber);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(content: Text('学習状況の保存に失敗しました。後でもう一度お試しください。')),
          );
      }
    }

    if (!context.mounted) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoLessonPage(
          course: course,
          lesson: lesson,
          lessonNumber: lessonNumber,
        ),
      ),
    );
  }

  void _previewLesson(BuildContext context) {
    if (course.lessons.isEmpty) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoLessonPage(
          course: course,
          lesson: course.lessons.first,
          lessonNumber: 1,
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String featureName) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('$featureNameは後で追加します。')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isTeacherMode ? '講座確認' : '講座詳細')),
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
            if (isTeacherMode) ...[
              const _TeacherModeNotice(),
              const SizedBox(height: 16),
            ],
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
            if (course.courseCode != null) ...[
              const SizedBox(height: 8),
              Text(
                '講座コード: ${course.courseCode}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
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
              _LessonTile(
                index: entry.$1 + 1,
                lesson: entry.$2,
                onTap: isTeacherMode
                    ? null
                    : () {
                        _openLesson(
                          context,
                          lesson: entry.$2,
                          lessonNumber: entry.$1 + 1,
                        );
                      },
              ),
            const SizedBox(height: 24),
            if (isTeacherMode)
              _TeacherActionButtons(
                onEditCourse: () => _showComingSoon(context, '講座編集'),
                onManageLessons: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TeacherLessonManagePage(course: course),
                    ),
                  );
                },
                onManageInteractions: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          TeacherInteractionManagePage(course: course),
                    ),
                  );
                },
                onPreview: () => _previewLesson(context),
              )
            else
              FilledButton.icon(
                onPressed: () {
                  if (course.lessons.isEmpty) {
                    return;
                  }

                  _openLesson(
                    context,
                    lesson: course.lessons.first,
                    lessonNumber: 1,
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

class _TeacherModeNotice extends StatelessWidget {
  const _TeacherModeNotice();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'この画面は先生用の確認画面です。編集機能は後で追加します。',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _TeacherActionButtons extends StatelessWidget {
  const _TeacherActionButtons({
    required this.onEditCourse,
    required this.onManageLessons,
    required this.onManageInteractions,
    required this.onPreview,
  });

  final VoidCallback onEditCourse;
  final VoidCallback onManageLessons;
  final VoidCallback onManageInteractions;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: onEditCourse,
          icon: const Icon(Icons.edit),
          label: const Text('講座を編集'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onManageLessons,
          icon: const Icon(Icons.playlist_add_check),
          label: const Text('レッスンを管理'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onManageInteractions,
          icon: const Icon(Icons.forum_outlined),
          label: const Text('公開メモ・質問を管理'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onPreview,
          icon: const Icon(Icons.visibility),
          label: const Text('プレビューを見る'),
        ),
      ],
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
  const _LessonTile({required this.index, required this.lesson, this.onTap});

  final int index;
  final CourseLesson lesson;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
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
