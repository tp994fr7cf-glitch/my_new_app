import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import 'course_create_page.dart';
import 'course_list_page.dart';
import 'learning_records_page.dart';
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
  });

  final User user;
  final Map<String, dynamic> profile;
  final List<String> roles;

  @override
  Widget build(BuildContext context) {
    return _HomeScaffold(
      title: '学習者ホーム',
      user: user,
      roles: roles,
      child: ListView(
        padding: const EdgeInsets.all(24),
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
          _ResumeLearningCard(user: user),
          _HomeActionCard(
            icon: Icons.timeline,
            title: '学習記録',
            description: '視聴記録、クイズ回答、質問コメントの記録を振り返れます。',
            buttonText: '学習記録を見る',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LearningRecordsPage(user: user),
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
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const CourseListPage()));
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
    );
  }
}

class _ResumeLearningCard extends StatelessWidget {
  const _ResumeLearningCard({required this.user});

  final User user;

  Stream<QuerySnapshot<Map<String, dynamic>>> _enrollmentStream() {
    if (Firebase.apps.isEmpty) {
      return const Stream.empty();
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('enrollments')
        .where('status', isEqualTo: 'inProgress')
        .snapshots();
  }

  void _resumeLearning(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> enrollment,
  ) {
    final data = enrollment.data() ?? {};
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

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortedEnrollments(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sortedDocs = [...docs];

    sortedDocs.sort((a, b) {
      final aUpdatedAt = a.data()['updatedAt'];
      final bUpdatedAt = b.data()['updatedAt'];
      if (aUpdatedAt is Timestamp && bUpdatedAt is Timestamp) {
        return bUpdatedAt.compareTo(aUpdatedAt);
      }
      return 0;
    });

    return sortedDocs;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _enrollmentStream(),
      builder: (context, snapshot) {
        final enrollments = snapshot.hasData
            ? _sortedEnrollments(snapshot.data!.docs)
            : <QueryDocumentSnapshot<Map<String, dynamic>>>[];

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
                else
                  for (final enrollment in enrollments) ...[
                    _EnrollmentResumeTile(
                      enrollment: enrollment,
                      onResume: () => _resumeLearning(context, enrollment),
                    ),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EnrollmentResumeTile extends StatelessWidget {
  const _EnrollmentResumeTile({
    required this.enrollment,
    required this.onResume,
  });

  final DocumentSnapshot<Map<String, dynamic>> enrollment;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final data = enrollment.data() ?? {};
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
            description: '作成した講座の一覧と講座コードを確認できます。',
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
    final intendedUse = profile['intendedUse'] as String?;
    final teacherApplicationStatus =
        profile['teacherApplicationStatus'] as String?;
    final organizationApplicationStatus =
        profile['organizationApplicationStatus'] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'アカウント情報',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('名前: ${user.displayName ?? '未設定'}'),
            Text('メール: ${user.email ?? '未設定'}'),
            Text('電話番号: ${user.phoneNumber ?? '未設定'}'),
            Text('現在の立場: ${_roleLabel(activeRole)}'),
            Text('持っている権限: ${roles.map(_roleLabel).join(' / ')}'),
            Text('利用目的: ${_intendedUseLabel(intendedUse)}'),
            Text('先生申請: ${_applicationStatusLabel(teacherApplicationStatus)}'),
            Text(
              '組織申請: ${_applicationStatusLabel(organizationApplicationStatus)}',
            ),
          ],
        ),
      ),
    );
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
