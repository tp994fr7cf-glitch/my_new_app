import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import 'course_detail_page.dart';

class TeacherCourseListPage extends StatelessWidget {
  const TeacherCourseListPage({
    super.key,
    required this.user,
    this.courseStream,
  });

  final User user;
  final Stream<List<Course>>? courseStream;

  Stream<List<Course>> _courses() {
    final providedStream = courseStream;
    if (providedStream != null) {
      return providedStream;
    }

    return FirebaseFirestore.instance
        .collection('courses')
        .where('instructorId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Course.fromFirestore).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自分の講座')),
      body: SafeArea(
        child: StreamBuilder<List<Course>>(
          stream: _courses(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _CourseLoadError(error: snapshot.error!);
            }

            final courses = snapshot.data ?? const [];
            if (courses.isEmpty) {
              return const _EmptyTeacherCourses();
            }

            courses.sort((a, b) => a.title.compareTo(b.title));

            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  '作成した講座',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('まずは閲覧のみです。編集や公開切り替えは後で追加します。'),
                const SizedBox(height: 24),
                for (final course in courses) ...[
                  _TeacherCourseCard(course: course),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TeacherCourseCard extends StatelessWidget {
  const _TeacherCourseCard({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              course.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('講座コード: ${course.courseCode ?? '未設定'}'),
            Text('カテゴリ: ${course.category}'),
            Text('レベル: ${course.level}'),
            Text('レッスン数: ${course.lessonCount}本'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CourseDetailPage(course: course),
                  ),
                );
              },
              child: const Text('講座詳細を見る'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTeacherCourses extends StatelessWidget {
  const _EmptyTeacherCourses();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('まだ作成した講座がありません。先生ホームから新しい講座を作成してください。'),
      ),
    );
  }
}

class _CourseLoadError extends StatelessWidget {
  const _CourseLoadError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('講座の読み込みに失敗しました: $error'),
      ),
    );
  }
}
