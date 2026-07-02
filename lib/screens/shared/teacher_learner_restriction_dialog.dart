import 'package:flutter/material.dart';

import '../../models/course.dart';
import '../../models/course_participant_identity.dart';
import '../../services/lesson_interaction_service.dart';

List<int> sortedCourseLessonNumbers(Course course) {
  if (course.lessons.isEmpty) {
    return const [1];
  }
  return [for (var i = 0; i < course.lessons.length; i++) i + 1];
}

int youngestCourseLessonNumber(Course course) =>
    sortedCourseLessonNumbers(course).first;

String lessonDropdownLabel(Course course, int lessonNumber) {
  final index = lessonNumber - 1;
  if (index >= 0 && index < course.lessons.length) {
    final lesson = course.lessons[index];
    return 'レッスン$lessonNumber: ${lesson.title}';
  }
  return 'レッスン$lessonNumber';
}

class TeacherLearnerRestrictionDialogResult {
  const TeacherLearnerRestrictionDialogResult({
    required this.targetLessonNumbers,
    required this.selectedMode,
    required this.bulkHide,
    required this.bulkUnhide,
    required this.bulkUnhidePolicy,
  });

  final List<int> targetLessonNumbers;
  final String selectedMode;
  final bool bulkHide;
  final bool bulkUnhide;
  final String bulkUnhidePolicy;
}

class TeacherLearnerRestrictionDialog extends StatefulWidget {
  const TeacherLearnerRestrictionDialog({
    super.key,
    required this.course,
    required this.courseId,
    required this.identity,
    required this.initialLessonNumber,
    required this.service,
    this.allowMultiLessonSelection = true,
  });

  final Course course;
  final String courseId;
  final CourseParticipantIdentity identity;
  final int initialLessonNumber;
  final LessonInteractionService service;
  final bool allowMultiLessonSelection;

  static Future<TeacherLearnerRestrictionDialogResult?> show({
    required BuildContext context,
    required Course course,
    required String courseId,
    required CourseParticipantIdentity identity,
    required int initialLessonNumber,
    required LessonInteractionService service,
    bool allowMultiLessonSelection = true,
  }) {
    return showDialog<TeacherLearnerRestrictionDialogResult>(
      context: context,
      builder: (dialogContext) {
        return TeacherLearnerRestrictionDialog(
          course: course,
          courseId: courseId,
          identity: identity,
          initialLessonNumber: initialLessonNumber,
          service: service,
          allowMultiLessonSelection: allowMultiLessonSelection,
        );
      },
    );
  }

  @override
  State<TeacherLearnerRestrictionDialog> createState() =>
      _TeacherLearnerRestrictionDialogState();
}

class _TeacherLearnerRestrictionDialogState
    extends State<TeacherLearnerRestrictionDialog> {
  late int _selectedSingleLesson;
  late bool _multiSelectEnabled;
  final Set<int> _selectedMultiLessons = <int>{};
  var _selectedMode = LessonInteractionService.learnerRestrictionModeNone;
  var _bulkHide = false;
  var _bulkUnhide = false;
  var _bulkUnhidePolicy =
      LessonInteractionService.bulkUnhideKeepIndividualHidden;
  var _loadingLessonState = false;

  List<int> get _lessonNumbers => sortedCourseLessonNumbers(widget.course);

  @override
  void initState() {
    super.initState();
    _selectedSingleLesson = _lessonNumbers.contains(widget.initialLessonNumber)
        ? widget.initialLessonNumber
        : youngestCourseLessonNumber(widget.course);
    _multiSelectEnabled = false;
    _loadSingleLessonState(_selectedSingleLesson);
  }

  Future<void> _loadSingleLessonState(int lessonNumber) async {
    setState(() {
      _loadingLessonState = true;
    });
    final state = await widget.service.loadLearnerRestrictionLessonState(
      courseId: widget.courseId,
      lessonNumber: lessonNumber,
      learnerId: widget.identity.userId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedMode = state.restrictionMode;
      _bulkHide = state.currentlyBulkHidden;
      _bulkUnhide = false;
      _bulkUnhidePolicy =
          LessonInteractionService.bulkUnhideKeepIndividualHidden;
      _loadingLessonState = false;
    });
  }

  void _onMultiSelectChanged(bool? value) {
    final enabled = value == true;
    setState(() {
      _multiSelectEnabled = enabled;
      if (enabled) {
        _selectedMode = LessonInteractionService.learnerRestrictionModeNone;
        _bulkHide = false;
        _bulkUnhide = false;
        _selectedMultiLessons.clear();
        _loadingLessonState = false;
        return;
      }
    });
    if (!enabled) {
      _loadSingleLessonState(_selectedSingleLesson);
    }
  }

  void _onSingleLessonChanged(int? lessonNumber) {
    if (lessonNumber == null || _multiSelectEnabled) {
      return;
    }
    setState(() {
      _selectedSingleLesson = lessonNumber;
    });
    _loadSingleLessonState(lessonNumber);
  }

  void _toggleMultiLesson(int lessonNumber, bool selected) {
    setState(() {
      if (selected) {
        _selectedMultiLessons.add(lessonNumber);
      } else {
        _selectedMultiLessons.remove(lessonNumber);
      }
    });
  }

  void _selectAllLessons() {
    setState(() {
      _selectedMultiLessons
        ..clear()
        ..addAll(_lessonNumbers);
    });
  }

  void _clearAllLessons() {
    setState(_selectedMultiLessons.clear);
  }

  void _submit() {
    final List<int> targetLessonNumbers;
    if (_multiSelectEnabled) {
      targetLessonNumbers = _selectedMultiLessons.toList()..sort();
    } else {
      targetLessonNumbers = [_selectedSingleLesson];
    }
    if (targetLessonNumbers.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('適用するレッスンを1つ以上選んでください。')),
      );
      return;
    }
    Navigator.of(context).pop(
      TeacherLearnerRestrictionDialogResult(
        targetLessonNumbers: targetLessonNumbers,
        selectedMode: _selectedMode,
        bulkHide: _bulkHide,
        bulkUnhide: _bulkUnhide,
        bulkUnhidePolicy: _bulkUnhidePolicy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('非公開詳細設定'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('対象ユーザー: ${widget.identity.userId}'),
            const SizedBox(height: 12),
            if (_loadingLessonState)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
            if (!_multiSelectEnabled) ...[
              DropdownButtonFormField<int>(
                value: _selectedSingleLesson,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'レッスン',
                ),
                items: [
                  for (final lessonNumber in _lessonNumbers)
                    DropdownMenuItem(
                      value: lessonNumber,
                      child: Text(lessonDropdownLabel(widget.course, lessonNumber)),
                    ),
                ],
                onChanged: _loadingLessonState ? null : _onSingleLessonChanged,
              ),
              const SizedBox(height: 12),
            ],
            if (widget.allowMultiLessonSelection) ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _multiSelectEnabled,
                title: const Text('複数から選択'),
                onChanged: _loadingLessonState ? null : _onMultiSelectChanged,
              ),
              if (_multiSelectEnabled) ...[
                const SizedBox(height: 8),
                const Text('適用するレッスン'),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _selectAllLessons,
                      child: const Text('全選択'),
                    ),
                    TextButton(
                      onPressed: _clearAllLessons,
                      child: const Text('全解除'),
                    ),
                  ],
                ),
                for (final lessonNumber in _lessonNumbers)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _selectedMultiLessons.contains(lessonNumber),
                    title: Text(
                      lessonDropdownLabel(widget.course, lessonNumber),
                    ),
                    onChanged: (value) {
                      _toggleMultiLesson(lessonNumber, value == true);
                    },
                  ),
                const SizedBox(height: 12),
              ],
            ],
            DropdownButtonFormField<String>(
              value: _selectedMode,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '制限モード',
              ),
              items: const [
                DropdownMenuItem(
                  value: LessonInteractionService.learnerRestrictionModeNone,
                  child: Text('制限なし'),
                ),
                DropdownMenuItem(
                  value: LessonInteractionService
                      .learnerRestrictionModeNoPublicReadOrPost,
                  child: Text('公開欄の閲覧と投稿を制限'),
                ),
                DropdownMenuItem(
                  value:
                      LessonInteractionService.learnerRestrictionModeNoPublicPost,
                  child: Text('公開欄への投稿のみ制限'),
                ),
              ],
              onChanged: _loadingLessonState
                  ? null
                  : (value) {
                      setState(() {
                        _selectedMode = widget.service
                            .normalizeLearnerRestrictionMode(value);
                      });
                    },
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _bulkHide,
              title: const Text('この受講者の既存公開投稿を一括で非公開にする'),
              onChanged: _loadingLessonState
                  ? null
                  : (value) {
                      setState(() {
                        _bulkHide = value == true;
                        if (_bulkHide) {
                          _bulkUnhide = false;
                        }
                      });
                    },
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _bulkUnhide,
              title: const Text('この受講者の公開投稿を一括で公開に戻す'),
              onChanged: _loadingLessonState
                  ? null
                  : (value) {
                      setState(() {
                        _bulkUnhide = value == true;
                        if (_bulkUnhide) {
                          _bulkHide = false;
                        }
                      });
                    },
            ),
            if (_bulkUnhide) ...[
              const SizedBox(height: 8),
              const Text('一括公開の方針'),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: LessonInteractionService.bulkUnhideKeepIndividualHidden,
                groupValue: _bulkUnhidePolicy,
                title: const Text('A: 個別非公開は維持'),
                onChanged: _loadingLessonState
                    ? null
                    : (value) {
                        setState(() {
                          _bulkUnhidePolicy =
                              value ??
                              LessonInteractionService
                                  .bulkUnhideKeepIndividualHidden;
                        });
                      },
              ),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: LessonInteractionService.bulkUnhideForceAllVisible,
                groupValue: _bulkUnhidePolicy,
                title: const Text('B: すべて公開に戻す'),
                onChanged: _loadingLessonState
                    ? null
                    : (value) {
                        setState(() {
                          _bulkUnhidePolicy =
                              value ??
                              LessonInteractionService
                                  .bulkUnhideKeepIndividualHidden;
                        });
                      },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: _loadingLessonState ? null : _submit,
          child: const Text('保存する'),
        ),
      ],
    );
  }
}
