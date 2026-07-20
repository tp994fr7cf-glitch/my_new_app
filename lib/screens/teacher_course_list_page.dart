import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/teacher_course_list_service.dart';
import '../utils/firebase_error_message.dart';
import 'course_detail_page.dart';

typedef TeacherCourseVisibilityUpdater =
    Future<void> Function(Course course, bool hidden);
typedef TeacherCourseOrderSaver =
    Future<void> Function(List<Course> orderedCourses);

class TeacherCourseListPage extends StatefulWidget {
  const TeacherCourseListPage({
    super.key,
    required this.user,
    this.courseStream,
    this.visibilityUpdater,
    this.orderSaver,
  });

  final User user;
  final Stream<List<Course>>? courseStream;
  final TeacherCourseVisibilityUpdater? visibilityUpdater;
  final TeacherCourseOrderSaver? orderSaver;

  @override
  State<TeacherCourseListPage> createState() => _TeacherCourseListPageState();
}

class _TeacherCourseListPageState extends State<TeacherCourseListPage> {
  final _service = const TeacherCourseListService();
  final _pendingCourseKeys = <String>{};
  final _hiddenOverrides = <String, bool>{};
  late final Stream<List<Course>> _courseStream;
  List<String>? _preferredVisibleIds;
  bool _isSavingOrder = false;

  @override
  void initState() {
    super.initState();
    _courseStream =
        widget.courseStream ?? _service.watchOwnCourses(widget.user.uid);
  }

  String _courseKey(Course course) =>
      course.id ?? 'local:${course.courseCode ?? course.title}';

  bool _isHidden(Course course) =>
      _hiddenOverrides[_courseKey(course)] ?? course.teacherListHidden;

  void _discardConfirmedOverrides(List<Course> courses) {
    for (final course in courses) {
      final key = _courseKey(course);
      final override = _hiddenOverrides[key];
      if (override == course.teacherListHidden) {
        _hiddenOverrides.remove(key);
      }
    }
  }

  Future<void> _setHidden(Course course, bool hidden) async {
    final key = _courseKey(course);
    if (_pendingCourseKeys.contains(key)) {
      return;
    }

    setState(() {
      _pendingCourseKeys.add(key);
      _hiddenOverrides[key] = hidden;
    });

    try {
      final updater = widget.visibilityUpdater;
      if (updater != null) {
        await updater(course, hidden);
      } else {
        await _service.setHidden(course: course, hidden: hidden);
      }
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(hidden ? '講座を管理一覧で非表示にしました。' : '講座を管理一覧に再表示しました。'),
            action: hidden
                ? SnackBarAction(
                    label: '元に戻す',
                    onPressed: () {
                      _setHidden(course, false);
                    },
                  )
                : null,
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _hiddenOverrides.remove(key);
      });
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              describeFirebaseError(
                error,
                permissionDeniedMessage: 'この講座の表示設定を変更する権限がありません。',
              ),
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _pendingCourseKeys.remove(key);
        });
      }
    }
  }

  Future<void> _reorderCourses(
    List<Course> visibleCourses,
    int oldIndex,
    int newIndex,
  ) async {
    if (_isSavingOrder) {
      return;
    }
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    if (oldIndex == newIndex) {
      return;
    }

    final previousIds = visibleCourses.map(_courseKey).toList();
    final reordered = [...visibleCourses];
    final movedCourse = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, movedCourse);
    setState(() {
      _preferredVisibleIds = reordered.map(_courseKey).toList();
      _isSavingOrder = true;
    });

    try {
      final saver = widget.orderSaver;
      if (saver != null) {
        await saver(reordered);
      } else {
        await _service.saveVisibleOrder(reordered);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _preferredVisibleIds = previousIds;
      });
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              describeFirebaseError(
                error,
                permissionDeniedMessage: '講座の並び順を変更する権限がありません。',
              ),
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingOrder = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自分の講座')),
      body: SafeArea(
        child: StreamBuilder<List<Course>>(
          stream: _courseStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _CourseLoadError(error: snapshot.error!);
            }

            final courses = snapshot.data ?? const <Course>[];
            if (courses.isEmpty) {
              return const _EmptyTeacherCourses();
            }

            _discardConfirmedOverrides(courses);
            final sortedCourses = sortTeacherCourses(
              courses,
              preferredIds: _preferredVisibleIds,
            );
            final visibleCourses = sortedCourses
                .where((course) => !_isHidden(course))
                .toList();
            final hiddenCourses = sortedCourses.where(_isHidden).toList();

            return CustomScrollView(
              slivers: [
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(24, 24, 24, 12),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '作成した講座',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text('右端の持ち手をドラッグして並び替えられます。非表示にしても学習者への公開状態は変わりません。'),
                      ],
                    ),
                  ),
                ),
                if (visibleCourses.isEmpty)
                  const SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    sliver: SliverToBoxAdapter(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('表示中の講座はありません。下の「非表示の講座」から再表示できます。'),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    sliver: SliverReorderableList(
                      itemCount: visibleCourses.length,
                      itemBuilder: (context, index) {
                        final course = visibleCourses[index];
                        final key = _courseKey(course);
                        return Padding(
                          key: ValueKey(key),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _TeacherCourseCard(
                            course: course,
                            isPending: _pendingCourseKeys.contains(key),
                            reorderIndex: index,
                            reorderEnabled: !_isSavingOrder,
                            onVisibilityChanged: () => _setHidden(course, true),
                          ),
                        );
                      },
                      onReorder: (oldIndex, newIndex) {
                        _reorderCourses(visibleCourses, oldIndex, newIndex);
                      },
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                  sliver: SliverToBoxAdapter(
                    child: _HiddenCoursesSection(
                      courses: hiddenCourses,
                      pendingCourseKeys: _pendingCourseKeys,
                      courseKey: _courseKey,
                      onRestore: (course) => _setHidden(course, false),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TeacherCourseCard extends StatelessWidget {
  const _TeacherCourseCard({
    required this.course,
    required this.isPending,
    required this.onVisibilityChanged,
    this.reorderIndex,
    this.reorderEnabled = false,
    this.isHidden = false,
  });

  final Course course;
  final bool isPending;
  final VoidCallback onVisibilityChanged;
  final int? reorderIndex;
  final bool reorderEnabled;
  final bool isHidden;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    course.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (reorderIndex != null)
                  Tooltip(
                    message: 'ドラッグして並び替え',
                    child: ReorderableDragStartListener(
                      index: reorderIndex!,
                      enabled: reorderEnabled,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('講座コード: ${course.courseCode ?? '未設定'}'),
            Text('カテゴリ: ${course.category}'),
            Text('レベル: ${course.level}'),
            Text('レッスン数: ${course.lessonCount}本'),
            const SizedBox(height: 8),
            Text('作成日時: ${formatTeacherCourseTimestamp(course.createdAt)}'),
            Text('最終編集: ${formatTeacherCourseTimestamp(course.updatedAt)}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CourseDetailPage(
                          course: course,
                          isTeacherMode: true,
                        ),
                      ),
                    );
                  },
                  child: const Text('講座詳細を見る'),
                ),
                OutlinedButton.icon(
                  onPressed: isPending ? null : onVisibilityChanged,
                  icon: isPending
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isHidden
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                  label: Text(isHidden ? '再表示' : '非表示'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HiddenCoursesSection extends StatelessWidget {
  const _HiddenCoursesSection({
    required this.courses,
    required this.pendingCourseKeys,
    required this.courseKey,
    required this.onRestore,
  });

  final List<Course> courses;
  final Set<String> pendingCourseKeys;
  final String Function(Course course) courseKey;
  final ValueChanged<Course> onRestore;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        key: const PageStorageKey('hidden-teacher-courses'),
        leading: const Icon(Icons.visibility_off_outlined),
        title: Text('非表示の講座（${courses.length}件）'),
        subtitle: const Text('タップして開くと再表示できます'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: courses.isEmpty
            ? const [
                Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('非表示の講座はありません。'),
                ),
              ]
            : [
                for (final course in courses)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _TeacherCourseCard(
                      course: course,
                      isPending: pendingCourseKeys.contains(courseKey(course)),
                      isHidden: true,
                      onVisibilityChanged: () => onRestore(course),
                    ),
                  ),
              ],
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

String formatTeacherCourseTimestamp(Timestamp? timestamp) {
  if (timestamp == null) {
    return '日時不明';
  }
  final date = timestamp.toDate().toLocal();
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.year}/$month/$day $hour:$minute';
}

class _CourseLoadError extends StatelessWidget {
  const _CourseLoadError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          describeFirebaseError(
            error,
            permissionDeniedMessage:
                '自分の講座一覧を読み込む権限がありません。再ログインするか、しばらく待ってから再試行してください。',
          ),
        ),
      ),
    );
  }
}
