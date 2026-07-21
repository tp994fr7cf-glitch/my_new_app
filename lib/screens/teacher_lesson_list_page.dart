import 'dart:async';

import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/course_catalog_service.dart';
import '../services/course_lesson_repository.dart';
import 'teacher_lesson_manage_page.dart';

class TeacherLessonListPage extends StatefulWidget {
  const TeacherLessonListPage({
    super.key,
    required this.course,
    this.courseStream,
    this.onAddLessonOverride,
  });

  final Course course;
  final Stream<Course>? courseStream;
  final Future<void> Function()? onAddLessonOverride;

  @override
  State<TeacherLessonListPage> createState() => _TeacherLessonListPageState();
}

class _TeacherLessonListPageState extends State<TeacherLessonListPage> {
  final _repository = const CourseLessonRepository();
  late final Stream<Course> _courseStream;
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    _courseStream =
        widget.courseStream ??
        const CourseCatalogService().watchCourse(widget.course) ??
        Stream.value(widget.course);
  }

  Future<void> _addLesson() async {
    final courseId = widget.course.id;
    if (courseId == null && widget.onAddLessonOverride == null) {
      return;
    }
    setState(() => _isAdding = true);
    try {
      final override = widget.onAddLessonOverride;
      if (override != null) {
        await override();
      } else {
        await _repository.createLesson(courseId: courseId!);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('レッスンを追加できませんでした: $error')));
      }
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('レッスンを管理')),
      body: SafeArea(
        child: StreamBuilder<Course>(
          stream: _courseStream,
          initialData: widget.course,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('レッスンの読み込みに失敗しました。'));
            }
            final course = snapshot.data ?? widget.course;
            final lessons = course.lessons;
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  course.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text('編集するレッスンを選んでください。保存は選択したレッスンだけに反映されます。'),
                const SizedBox(height: 20),
                if (lessons.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('レッスンがありません。「レッスンを追加」から作成してください。'),
                    ),
                  )
                else
                  for (final entry in lessons.indexed)
                    Card(
                      child: ListTile(
                        key: ValueKey('lesson-${entry.$2.id ?? entry.$1}'),
                        leading: CircleAvatar(child: Text('${entry.$1 + 1}')),
                        title: Text(entry.$2.title),
                        subtitle: Text(entry.$2.duration),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: entry.$2.id == null
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => TeacherLessonManagePage(
                                      course: course,
                                      lessonId: entry.$2.id!,
                                    ),
                                  ),
                                );
                              },
                      ),
                    ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _isAdding ? null : () => unawaited(_addLesson()),
                  icon: _isAdding
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: const Text('レッスンを追加'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
