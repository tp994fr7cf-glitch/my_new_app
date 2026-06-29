import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/public_user_profile.dart';
import '../services/course_privacy_service.dart';
import 'course_entry_gate.dart';
import 'course_create_page.dart';
import 'course_list_page.dart';
import 'learning_records_page.dart';
import 'public_user_profile_page.dart';
import 'role_switch_page.dart';
import 'teacher_application_page.dart';
import 'teacher_course_list_page.dart';
import 'video_lesson_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.user, required this.profile});

  final User user;
  final Map<String, dynamic> profile;

  List<String> _roles() {
    final roles = profile['roles'];
    if (roles is List && roles.isNotEmpty) {
      return roles.whereType<String>().toList();
    }

    final legacyRole = profile['role'];
    if (legacyRole is String && legacyRole.isNotEmpty) {
      return [legacyRole];
    }

    return ['student'];
  }

  String _activeRole() {
    final activeRole = profile['activeRole'];
    final roles = _roles();

    if (activeRole is String && roles.contains(activeRole)) {
      return activeRole;
    }

    return roles.first;
  }

  @override
  Widget build(BuildContext context) {
    final roles = _roles();
    final activeRole = _activeRole();

    return switch (activeRole) {
      'teacher' => TeacherHomePage(user: user, profile: profile, roles: roles),
      'schoolAdmin' || 'organization' => OrganizationHomePage(
        user: user,
        profile: profile,
        roles: roles,
      ),
      _ => StudentHomePage(user: user, profile: profile, roles: roles),
    };
  }
}

class StudentHomePage extends StatelessWidget {
  const StudentHomePage({
    super.key,
    required this.user,
    required this.profile,
    required this.roles,
    this.enrollmentRecordsStream,
  });

  final User user;
  final Map<String, dynamic> profile;
  final List<String> roles;
  final Stream<List<Map<String, dynamic>>>? enrollmentRecordsStream;

  @override
  Widget build(BuildContext context) {
    return _HomeScaffold(
      title: '学習者ホーム',
      user: user,
      roles: roles,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'おかえりなさい',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(user.displayName ?? user.email ?? '学習者さん'),
            const SizedBox(height: 24),
            _ProfileSummaryCard(user: user, profile: profile, roles: roles),
            const SizedBox(height: 16),
            _ResumeLearningCard(
              user: user,
              enrollmentRecordsStream: enrollmentRecordsStream,
            ),
            _HomeActionCard(
              icon: Icons.timeline,
              title: '学習記録',
              description: '視聴記録、クイズ回答、質問コメントの記録を振り返れます。',
              buttonText: '学習記録を見る',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LearningRecordsPage(
                      user: user,
                      activeCommentRole: profile['activeRole'] as String?,
                    ),
                  ),
                );
              },
            ),
            _HomeActionCard(
              icon: Icons.search,
              title: '講座を探す',
              description: '次に作る講座一覧画面への入口です。Udemyのようなカード一覧に育てます。',
              buttonText: '講座一覧へ',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CourseListPage()),
                );
              },
            ),
            _HomeActionCard(
              icon: Icons.star,
              title: 'おすすめ講座',
              description: 'あなたに合いそうな講座を表示する予定です。今は仮の枠だけ用意しています。',
              buttonText: 'おすすめを見る',
              onPressed: () {},
            ),
            _HomeActionCard(
              icon: Icons.school,
              title: '先生として活動したい場合',
              description: '先生申請の状況確認や、申請の送信ができます。',
              buttonText: '申請状況を見る',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        TeacherApplicationPage(user: user, profile: profile),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

const int _resumeLearningPreviewLimit = 3;

class _ResumeEnrollment {
  const _ResumeEnrollment({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;
}

Stream<List<_ResumeEnrollment>> _enrollmentRecordsStreamFor(User user) {
  if (Firebase.apps.isEmpty) {
    return Stream.value(const []);
  }

  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('enrollments')
      .where('status', isEqualTo: 'inProgress')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => _ResumeEnrollment(id: doc.id, data: doc.data()))
            .toList(),
      );
}

Stream<List<_ResumeEnrollment>>? _providedEnrollmentRecordsStream(
  Stream<List<Map<String, dynamic>>>? stream,
) {
  if (stream == null) {
    return null;
  }

  return stream.map(
    (records) => [
      for (final entry in records.indexed)
        _ResumeEnrollment(
          id: entry.$2['courseId'] as String? ?? 'enrollment-${entry.$1}',
          data: entry.$2,
        ),
    ],
  );
}

List<_ResumeEnrollment> _sortedEnrollments(List<_ResumeEnrollment> docs) {
  final sortedDocs = [...docs];

  sortedDocs.sort((a, b) {
    final aUpdatedAt = a.data['updatedAt'];
    final bUpdatedAt = b.data['updatedAt'];
    if (aUpdatedAt is Timestamp && bUpdatedAt is Timestamp) {
      return bUpdatedAt.compareTo(aUpdatedAt);
    }
    return 0;
  });

  return sortedDocs;
}

Future<void> _saveResumeLearningEvent({
  required User user,
  required String courseId,
  required Course course,
  required CourseLesson lesson,
  required int lessonNumber,
}) async {
  final now = FieldValue.serverTimestamp();
  final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
  final batch = FirebaseFirestore.instance.batch()
    ..set(userRef.collection('enrollments').doc(courseId), {
      'updatedAt': now,
      'lastLessonNumber': lessonNumber,
      'lastLessonTitle': lesson.title,
    }, SetOptions(merge: true))
    ..set(userRef.collection('learningEvents').doc(), {
      'userId': user.uid,
      'type': 'lessonOpened',
      'courseId': courseId,
      'courseTitle': course.title,
      'lessonNumber': lessonNumber,
      'lessonTitle': lesson.title,
      'createdAt': now,
    });

  await batch.commit();
}

Future<void> _resumeLearningFromEnrollment(
  BuildContext context, {
  required User user,
  required _ResumeEnrollment enrollment,
}) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final data = enrollment.data;
  final courseData = data['course'];
  if (courseData is! Map) {
    return;
  }

  final course = Course.fromMap(courseData, id: data['courseId'] as String?);
  if (course.lessons.isEmpty) {
    return;
  }

  final savedLessonNumber = (data['lastLessonNumber'] as num?)?.toInt() ?? 1;
  final lessonNumber = savedLessonNumber.clamp(1, course.lessons.length);
  final lesson = course.lessons[lessonNumber - 1];
  final courseId = data['courseId'] as String? ?? course.id ?? enrollment.id;

  final bool canEnter;
  try {
    canEnter = await ensureCourseEntryAccess(
      context,
      course: course,
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

  navigator.push(
    MaterialPageRoute(
      builder: (_) => VideoLessonPage(
        course: course,
        lesson: lesson,
        lessonNumber: lessonNumber,
      ),
    ),
  );

  _saveResumeLearningEvent(
    user: user,
    courseId: courseId,
    course: course,
    lesson: lesson,
    lessonNumber: lessonNumber,
  ).catchError((_) {
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        const SnackBar(content: Text('学習記録の保存に失敗しました。後でもう一度お試しください。')),
      );
  });
}

class _ResumeLearningCard extends StatelessWidget {
  const _ResumeLearningCard({required this.user, this.enrollmentRecordsStream});

  final User user;
  final Stream<List<Map<String, dynamic>>>? enrollmentRecordsStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<_ResumeEnrollment>>(
      stream:
          _providedEnrollmentRecordsStream(enrollmentRecordsStream) ??
          _enrollmentRecordsStreamFor(user),
      builder: (context, snapshot) {
        final enrollments = snapshot.hasData
            ? _sortedEnrollments(snapshot.data!)
            : <_ResumeEnrollment>[];
        final previewEnrollments = enrollments
            .take(_resumeLearningPreviewLimit)
            .toList();

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.play_circle, size: 40),
                const SizedBox(height: 12),
                const Text(
                  '学習中の講座',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Text('学習状況を確認しています...')
                else if (enrollments.isEmpty)
                  const Text('受講中の講座や前回の続きは、ここに表示していきます。')
                else ...[
                  for (final enrollment in previewEnrollments) ...[
                    _EnrollmentResumeTile(
                      enrollment: enrollment,
                      onResume: () async {
                        await _resumeLearningFromEnrollment(
                          context,
                          user: user,
                          enrollment: enrollment,
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (enrollments.length > _resumeLearningPreviewLimit)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _AllResumeLearningPage(
                                user: user,
                                enrollmentRecordsStream:
                                    enrollmentRecordsStream,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.list),
                        label: Text('もっと見る（全${enrollments.length}件）'),
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AllResumeLearningPage extends StatelessWidget {
  const _AllResumeLearningPage({
    required this.user,
    this.enrollmentRecordsStream,
  });

  final User user;
  final Stream<List<Map<String, dynamic>>>? enrollmentRecordsStream;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('学習中の講座')),
      body: SafeArea(
        child: StreamBuilder<List<_ResumeEnrollment>>(
          stream:
              _providedEnrollmentRecordsStream(enrollmentRecordsStream) ??
              _enrollmentRecordsStreamFor(user),
          builder: (context, snapshot) {
            final enrollments = snapshot.hasData
                ? _sortedEnrollments(snapshot.data!)
                : <_ResumeEnrollment>[];

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (enrollments.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('受講中の講座や前回の続きは、ここに表示していきます。'),
              );
            }

            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'すべての学習中講座',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('全${enrollments.length}件'),
                const SizedBox(height: 16),
                for (final enrollment in enrollments) ...[
                  _EnrollmentResumeTile(
                    enrollment: enrollment,
                    onResume: () async {
                      await _resumeLearningFromEnrollment(
                        context,
                        user: user,
                        enrollment: enrollment,
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EnrollmentResumeTile extends StatelessWidget {
  const _EnrollmentResumeTile({
    required this.enrollment,
    required this.onResume,
  });

  final _ResumeEnrollment enrollment;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final data = enrollment.data;
    final courseData = data['course'];
    final courseTitle = courseData is Map
        ? courseData['title'] as String? ?? '受講中の講座'
        : '受講中の講座';
    final lastLessonTitle = data['lastLessonTitle'] as String? ?? '前回の続き';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              courseTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('前回: $lastLessonTitle'),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: onResume,
                child: const Text('学習を再開'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TeacherHomePage extends StatelessWidget {
  const TeacherHomePage({
    super.key,
    required this.user,
    required this.profile,
    required this.roles,
  });

  final User user;
  final Map<String, dynamic> profile;
  final List<String> roles;

  @override
  Widget build(BuildContext context) {
    return _HomeScaffold(
      title: '先生ホーム',
      user: user,
      roles: roles,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            '先生として利用中',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('講座作成や動画投稿機能は、今後ここに追加していきます。'),
          const SizedBox(height: 24),
          _ProfileSummaryCard(user: user, profile: profile, roles: roles),
          const SizedBox(height: 16),
          _HomeActionCard(
            icon: Icons.video_library,
            title: '自分の講座',
            description: '作成した講座の一覧と講座コードを確認できます。講座詳細から本名同意設定も管理できます。',
            buttonText: '講座を管理',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TeacherCourseListPage(user: user),
                ),
              );
            },
          ),
          _HomeActionCard(
            icon: Icons.add_circle,
            title: '新しい講座を作成',
            description: '講座タイトル、説明、レッスン構成を登録します。講座コードも自動発行されます。',
            buttonText: '講座作成へ',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CourseCreatePage(user: user)),
              );
            },
          ),
          _HomeActionCard(
            icon: Icons.question_answer,
            title: '質問・コメント対応',
            description: '受講者からの質問やコメントを確認する場所になります。',
            buttonText: '質問を見る',
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class OrganizationHomePage extends StatelessWidget {
  const OrganizationHomePage({
    super.key,
    required this.user,
    required this.profile,
    required this.roles,
  });

  final User user;
  final Map<String, dynamic> profile;
  final List<String> roles;

  @override
  Widget build(BuildContext context) {
    return _HomeScaffold(
      title: '組織ホーム',
      user: user,
      roles: roles,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            '組織として利用中',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('学校・塾・企業向けの管理機能は、今後ここに追加していきます。'),
          const SizedBox(height: 24),
          _ProfileSummaryCard(user: user, profile: profile, roles: roles),
          const SizedBox(height: 16),
          _HomeActionCard(
            icon: Icons.groups,
            title: '所属ユーザー管理',
            description: '所属する先生や生徒を管理する画面を後で作ります。',
            buttonText: 'ユーザー管理へ',
            onPressed: () {},
          ),
          _HomeActionCard(
            icon: Icons.assignment,
            title: '研修・授業コース',
            description: '組織内で使う講座や研修コースを管理する場所になります。',
            buttonText: 'コース管理へ',
            onPressed: () {},
          ),
          _HomeActionCard(
            icon: Icons.insights,
            title: '利用状況',
            description: '学習進捗や受講状況の確認機能をここに追加していきます。',
            buttonText: '利用状況を見る',
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _HomeScaffold extends StatelessWidget {
  const _HomeScaffold({
    required this.title,
    required this.user,
    required this.roles,
    required this.child,
  });

  final String title;
  final User user;
  final List<String> roles;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (roles.length > 1)
            IconButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RoleSwitchPage(user: user, roles: roles),
                  ),
                );
              },
              icon: const Icon(Icons.swap_horiz),
              tooltip: '立場を切り替える',
            ),
          IconButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'ログアウト',
          ),
        ],
      ),
      body: SafeArea(child: child),
    );
  }
}

class _ProfileSummaryCard extends StatelessWidget {
  const _ProfileSummaryCard({
    required this.user,
    required this.profile,
    required this.roles,
  });

  final User user;
  final Map<String, dynamic> profile;
  final List<String> roles;
  static const _coursePrivacyService = CoursePrivacyService();

  String _roleLabel(String role) {
    return switch (role) {
      'student' => '学習者',
      'teacher' => '先生',
      'schoolAdmin' => '学校・組織管理者',
      'admin' => '運営管理者',
      _ => role,
    };
  }

  String _intendedUseLabel(String? intendedUse) {
    return switch (intendedUse) {
      'learner' => '学習者',
      'teacher' => '先生として申請中',
      'organization' => '学校・塾・企業として申請中',
      _ => '未設定',
    };
  }

  String _applicationStatusLabel(String? status) {
    return switch (status) {
      'pending' => '申請中',
      'approved' => '承認済み',
      'rejected' => '却下',
      'none' => 'なし',
      _ => 'なし',
    };
  }

  @override
  Widget build(BuildContext context) {
    final activeRole = profile['activeRole'] as String? ?? roles.first;
    final publicProfileRole = activeRole == publicUserProfileRoleTeacher
        ? publicUserProfileRoleTeacher
        : publicUserProfileRoleStudent;
    final intendedUse = profile['intendedUse'] as String?;
    final teacherApplicationStatus =
        profile['teacherApplicationStatus'] as String?;
    final organizationApplicationStatus =
        profile['organizationApplicationStatus'] as String?;
    final legalName = (profile['legalName'] as String?)?.trim() ?? '';
    final hasLegalName = legalName.isNotEmpty;

    return StreamBuilder<PublicUserProfile>(
      stream: publicUserProfileStream(
        userId: user.uid,
        role: publicProfileRole,
        fallbackDisplayName: user.displayName,
      ),
      builder: (context, snapshot) {
        final publicProfile =
            snapshot.data ??
            fallbackPublicUserProfile(
              userId: user.uid,
              role: publicProfileRole,
              displayName: user.displayName,
            );
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PublicProfileAvatar(profile: publicProfile, radius: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'プロフィール',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(publicProfile.displayName),
                          Text('現在の立場: ${_roleLabel(activeRole)}'),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EditPublicUserProfilePage(
                              userId: user.uid,
                              role: publicProfileRole,
                              initialProfile: publicProfile,
                            ),
                          ),
                        );
                      },
                      child: const Text('編集'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  publicProfile.bio.isEmpty
                      ? '自己紹介はまだありません。'
                      : publicProfile.bio,
                ),
                const Divider(height: 24),
                Text('持っている権限: ${roles.map(_roleLabel).join(' / ')}'),
                Text('利用目的: ${_intendedUseLabel(intendedUse)}'),
                Text(
                  '先生申請: ${_applicationStatusLabel(teacherApplicationStatus)}',
                ),
                Text(
                  '組織申請: ${_applicationStatusLabel(organizationApplicationStatus)}',
                ),
                const SizedBox(height: 8),
                if (hasLegalName)
                  Text('本名（本人のみ表示）: $legalName')
                else
                  Row(
                    children: [
                      const Expanded(child: Text('本名（氏名）は未登録です（任意）。')),
                      OutlinedButton(
                        onPressed: () {
                          _showLegalNameRegisterDialog(context, user.uid);
                        },
                        child: const Text('本名を登録'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showLegalNameRegisterDialog(
    BuildContext context,
    String userId,
  ) async {
    final controller = TextEditingController();
    var isSaving = false;
    String? errorText;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('本名（氏名）を登録'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('本名は一度登録すると、本人では変更できません。'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    enabled: !isSaving,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '本名（氏名）',
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final legalName = controller.text.trim();
                          if (legalName.isEmpty) {
                            setDialogState(() {
                              errorText = '本名を入力してください。';
                            });
                            return;
                          }
                          setDialogState(() {
                            isSaving = true;
                            errorText = null;
                          });
                          try {
                            await _coursePrivacyService.setLegalNameIfAbsent(
                              userId: userId,
                              legalName: legalName,
                            );
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          } catch (error) {
                            setDialogState(() {
                              errorText = '$error';
                              isSaving = false;
                            });
                          }
                        },
                  child: const Text('登録する'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
  }
}

class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonText,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonText;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onPressed, child: Text(buttonText)),
          ],
        ),
      ),
    );
  }
}
