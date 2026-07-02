import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/course_participant_identity.dart';
import '../models/course_privacy_consent.dart';
import '../models/public_user_profile.dart';
import '../services/course_catalog_service.dart';
import '../services/course_identity_service.dart';
import '../services/course_privacy_service.dart';
import 'course_entry_gate.dart';
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
  static const _courseCatalogService = CourseCatalogService();
  static const _courseIdentityService = CourseIdentityService();
  static const _coursePrivacyService = CoursePrivacyService();

  String _courseIdFor(Course activeCourse) => activeCourse.storageId;

  Future<void> _openAliasUpdateDialog(
    BuildContext context, {
    required CourseParticipantIdentity identity,
    required String userId,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    var draftDisplayName = identity.safeAliasDisplayName;
    var selectedColor = identity.safeAliasAvatarColorName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('講座専用表示を変更'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: draftDisplayName,
                      maxLength: 40,
                      onChanged: (value) {
                        draftDisplayName = value;
                      },
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: '講座専用の名前',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in profileAvatarColors.entries)
                          ChoiceChip(
                            label: Text(entry.key),
                            selected: selectedColor == entry.key,
                            avatar: CircleAvatar(backgroundColor: entry.value),
                            onSelected: (_) {
                              setDialogState(() {
                                selectedColor = entry.key;
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('保存する'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    final safeName = draftDisplayName.trim();
    if (safeName.isEmpty) {
      messenger
        ?..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('講座専用の名前を入力してください。')));
      return;
    }
    try {
      await _courseIdentityService.updateAlias(
        courseId: _courseIdFor(course),
        userId: userId,
        aliasDisplayName: safeName,
        aliasAvatarColorName: selectedColor,
        updatedByUserId: userId,
        updatedByRole: 'student',
        force: false,
      );
    } catch (_) {
      messenger
        ?..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('講座専用プロフィールの保存に失敗しました。')));
      return;
    }
    try {
      await _courseIdentityService.rewriteCourseAuthorSnapshots(
        courseId: _courseIdFor(course),
        userId: userId,
        snapshot: CourseAuthorSnapshot(
          displayName: safeName,
          avatarColorName: selectedColor,
          profileVisible: false,
          identityMode: courseIdentityModeAlias,
        ),
      );
      messenger
        ?..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('講座専用プロフィールを更新しました。')));
    } catch (_) {
      messenger
        ?..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('プロフィール変更は保存できましたが、過去投稿の表示反映で失敗しました。')),
        );
    }
  }

  Future<void> _revealProfileIdentity(
    BuildContext context, {
    required String userId,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('プロフィール公開へ切替'),
          content: const Text('この講座では講座専用表示を廃止し、プロフィール情報を公開します。この操作は取り消せません。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('公開する'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    try {
      await _courseIdentityService.revealProfileIdentity(
        courseId: _courseIdFor(course),
        userId: userId,
        updatedByUserId: userId,
        updatedByRole: 'student',
      );
      final snapshot = await _courseIdentityService.resolveAuthorSnapshot(
        courseId: _courseIdFor(course),
        userId: userId,
        fallbackDisplayName:
            FirebaseAuth.instance.currentUser?.displayName ?? '学習者',
        role: publicUserProfileRoleStudent,
      );
      await _courseIdentityService.rewriteCourseAuthorSnapshots(
        courseId: _courseIdFor(course),
        userId: userId,
        snapshot: snapshot,
      );
      messenger
        ?..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('プロフィール公開へ切り替えました。講座専用表示には戻せません。')),
        );
    } catch (_) {
      messenger
        ?..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('プロフィール公開は保存できましたが、過去投稿の表示反映で失敗しました。')),
        );
    }
  }

  Future<void> _saveLearningProgress({
    required Course activeCourse,
    required CourseLesson lesson,
    required int lessonNumber,
  }) async {
    if (Firebase.apps.isEmpty) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final courseId = _courseIdFor(activeCourse);
    final firestore = FirebaseFirestore.instance;
    final enrollmentRef = firestore
        .collection('users')
        .doc(user.uid)
        .collection('enrollments')
        .doc(courseId);
    final eventRef = firestore
        .collection('users')
        .doc(user.uid)
        .collection('learningEvents')
        .doc();
    final now = FieldValue.serverTimestamp();
    final courseSnapshot = {'id': courseId, ...activeCourse.toFirestore()};

    final batch = firestore.batch()
      ..set(enrollmentRef, {
        'userId': user.uid,
        'courseId': courseId,
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
        'courseId': courseId,
        'courseTitle': activeCourse.title,
        'lessonNumber': lessonNumber,
        'lessonTitle': lesson.title,
        'createdAt': now,
      });

    await batch.commit();
    try {
      await _coursePrivacyService.syncPeerLegalNameShareForEnrollment(
        userId: user.uid,
        courseId: courseId,
      );
    } on FirebaseException {
      // Do not block lesson opening if peer-share sync fails.
    }
  }

  Future<void> _openLesson(
    BuildContext context, {
    required Course activeCourse,
    required CourseLesson lesson,
    required int lessonNumber,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final user = Firebase.apps.isNotEmpty
        ? FirebaseAuth.instance.currentUser
        : null;
    if (!isTeacherMode && user != null) {
      final bool canEnter;
      try {
        canEnter = await ensureCourseEntryAccess(
          context,
          course: activeCourse,
          user: user,
        );
      } catch (_) {
        messenger
          ?..clearSnackBars()
          ..showSnackBar(
            const SnackBar(content: Text('受講状態の確認中にエラーが発生しました。もう一度お試しください。')),
          );
        return;
      }
      if (!canEnter) {
        return;
      }
    }
    try {
      await _saveLearningProgress(
        activeCourse: activeCourse,
        lesson: lesson,
        lessonNumber: lessonNumber,
      );
    } catch (_) {
      messenger
        ?..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('学習状況の保存に失敗しました。後でもう一度お試しください。')),
        );
    }

    if (!context.mounted) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoLessonPage(
          course: activeCourse,
          lesson: lesson,
          lessonNumber: lessonNumber,
        ),
      ),
    );
  }

  void _previewLesson(BuildContext context, Course activeCourse) {
    if (activeCourse.lessons.isEmpty) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoLessonPage(
          course: activeCourse,
          lesson: activeCourse.lessons.first,
          lessonNumber: 1,
          isTeacherPreview: true,
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
    final courseStream = _courseCatalogService.watchCourse(course);
    if (courseStream == null) {
      return _buildPage(context, course);
    }

    return StreamBuilder<Course>(
      stream: courseStream,
      initialData: course,
      builder: (context, snapshot) {
        return _buildPage(context, snapshot.data ?? course);
      },
    );
  }

  Widget _buildPage(BuildContext context, Course activeCourse) {
    final currentUser = Firebase.apps.isNotEmpty
        ? FirebaseAuth.instance.currentUser
        : null;
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
                Chip(label: Text(activeCourse.category)),
                Chip(label: Text(activeCourse.level)),
                Chip(label: Text(activeCourse.priceLabel)),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              activeCourse.title,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '講師: ${activeCourse.instructorName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (activeCourse.courseCode != null) ...[
              const SizedBox(height: 8),
              Text(
                '講座コード: ${activeCourse.courseCode}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.star, size: 20),
                const SizedBox(width: 4),
                Text(activeCourse.rating.toStringAsFixed(1)),
                const SizedBox(width: 16),
                const Icon(Icons.schedule, size: 20),
                const SizedBox(width: 4),
                Text(activeCourse.duration),
                const SizedBox(width: 16),
                const Icon(Icons.list_alt, size: 20),
                const SizedBox(width: 4),
                Text('${activeCourse.lessonCount}本'),
              ],
            ),
            const SizedBox(height: 24),
            const _SectionTitle('講座概要'),
            const SizedBox(height: 8),
            Text(activeCourse.description),
            const SizedBox(height: 24),
            const _SectionTitle('この講座で学べること'),
            const SizedBox(height: 8),
            const _BulletText('録画済み動画で自分のペースで学習できます。'),
            const _BulletText('基礎から順番に進められるレッスン構成です。'),
            const _BulletText('今後、コメントや学習記録と連携できる形に育てます。'),
            if (!isTeacherMode && currentUser != null) ...[
              const SizedBox(height: 24),
              const _SectionTitle('この講座での表示設定'),
              const SizedBox(height: 8),
              StreamBuilder<CourseParticipantIdentity?>(
                stream: _courseIdentityService.identityStream(
                  courseId: _courseIdFor(activeCourse),
                  userId: currentUser.uid,
                ),
                builder: (context, snapshot) {
                  final identity = snapshot.data;
                  if (identity == null) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          '受講開始時に、講座専用の名前・アイコンを設定できます。設定しない場合はプロフィール表示になります。',
                        ),
                      ),
                    );
                  }
                  final modeLabel = identity.isAliasMode
                      ? '講座専用の名前・アイコンを使用中'
                      : 'プロフィール表示を使用中';
                  final detail = identity.isAliasMode
                      ? '講座専用名: ${identity.safeAliasDisplayName}'
                      : identity.aliasConfiguredAtEnrollment
                      ? '講座専用表示は廃止済みです（再設定できません）'
                      : '受講開始時に講座専用表示を使わない設定でした（再設定できません）';
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            modeLabel,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(detail),
                          const SizedBox(height: 8),
                          if (identity.isAliasMode)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () {
                                    _openAliasUpdateDialog(
                                      context,
                                      identity: identity,
                                      userId: currentUser.uid,
                                    );
                                  },
                                  child: const Text('講座専用表示を変更'),
                                ),
                                FilledButton(
                                  onPressed: () {
                                    _revealProfileIdentity(
                                      context,
                                      userId: currentUser.uid,
                                    );
                                  },
                                  child: const Text('プロフィール情報を公開する'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              StreamBuilder<CourseEntryRequirement>(
                stream: _coursePrivacyService.watchEntryRequirement(
                  userId: currentUser.uid,
                  courseId: _courseIdFor(activeCourse),
                ),
                builder: (context, snapshot) {
                  final requirement = snapshot.data;
                  final canShowPeerNames =
                      requirement?.policy.shareAmongLearnersEnabled == true &&
                      requirement?.isConsentSatisfied == true;
                  if (!canShowPeerNames) {
                    return const SizedBox.shrink();
                  }
                  return StreamBuilder<List<String>>(
                    stream: _coursePrivacyService.peerLegalNamesStream(
                      _courseIdFor(activeCourse),
                    ),
                    builder: (context, namesSnapshot) {
                      final names = namesSnapshot.data ?? const <String>[];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'この講座で共有されている本名',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              const Text('この一覧は本名のみを表示します。プロフィール情報とは結びつきません。'),
                              const SizedBox(height: 8),
                              if (names.isEmpty)
                                const Text('表示できる本名はまだありません。')
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final name in names)
                                      Chip(label: Text(name)),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
            const SizedBox(height: 24),
            const _SectionTitle('レッスン一覧'),
            const SizedBox(height: 8),
            for (final entry in activeCourse.lessons.indexed)
              _LessonTile(
                index: entry.$1 + 1,
                lesson: entry.$2,
                onTap: isTeacherMode
                    ? null
                    : () {
                        _openLesson(
                          context,
                          activeCourse: activeCourse,
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
                      builder: (_) =>
                          TeacherLessonManagePage(course: activeCourse),
                    ),
                  );
                },
                onManageCourseSettings: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          TeacherInteractionManagePage(course: activeCourse),
                    ),
                  );
                },
                onPreview: () => _previewLesson(context, activeCourse),
              )
            else
              FilledButton.icon(
                onPressed: () {
                  if (activeCourse.lessons.isEmpty) {
                    return;
                  }

                  _openLesson(
                    context,
                    activeCourse: activeCourse,
                    lesson: activeCourse.lessons.first,
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
    required this.onManageCourseSettings,
    required this.onPreview,
  });

  final VoidCallback onEditCourse;
  final VoidCallback onManageLessons;
  final VoidCallback onManageCourseSettings;
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
          onPressed: onManageCourseSettings,
          icon: const Icon(Icons.settings_outlined),
          label: const Text('講座設定'),
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
