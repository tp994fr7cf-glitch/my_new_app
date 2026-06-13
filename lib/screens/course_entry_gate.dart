import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/course_participant_identity.dart';
import '../models/course_privacy_consent.dart';
import '../models/public_user_profile.dart';
import '../services/course_identity_service.dart';
import '../services/course_privacy_service.dart';

const _courseEntryPrivacyService = CoursePrivacyService();
const _courseEntryIdentityService = CourseIdentityService();

Future<bool> _hasExistingEnrollment({
  required String userId,
  required String courseId,
}) async {
  if (Firebase.apps.isEmpty || userId.isEmpty || courseId.isEmpty) {
    return false;
  }
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('enrollments')
        .doc(courseId)
        .get();
    return snapshot.exists;
  } on FirebaseException {
    return false;
  }
}

Future<bool> ensureCourseEntryAccess(
  BuildContext context, {
  required Course course,
  required User user,
  bool showBlockedMessage = true,
}) async {
  if (Firebase.apps.isEmpty) {
    return true;
  }
  final courseId = course.storageId;
  if (courseId.isEmpty) {
    if (showBlockedMessage && context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('講座情報の読み込みに失敗しました。')));
    }
    return false;
  }

  var requirement = await _courseEntryPrivacyService.evaluateEntryRequirement(
    userId: user.uid,
    courseId: courseId,
  );
  if (requirement.policy.requiresAnyConsent && !requirement.canEnter) {
    if (!context.mounted) {
      return false;
    }
    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            CoursePrivacyConsentPage(course: course, requirement: requirement),
      ),
    );
    if (accepted != true) {
      if (showBlockedMessage && context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('同意が完了するまで講座を開けません。')));
      }
      return false;
    }
    requirement = await _courseEntryPrivacyService.evaluateEntryRequirement(
      userId: user.uid,
      courseId: courseId,
    );
    if (!requirement.canEnter) {
      if (showBlockedMessage && context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(content: Text('同意情報を確認できませんでした。時間をおいて再試行してください。')),
          );
      }
      return false;
    }
  }

  final identity = await _courseEntryIdentityService.loadIdentity(
    courseId: courseId,
    userId: user.uid,
  );
  final hasExistingEnrollment = await _hasExistingEnrollment(
    userId: user.uid,
    courseId: courseId,
  );
  if (identity == null) {
    if (hasExistingEnrollment) {
      try {
        await _courseEntryIdentityService.ensureIdentityAtEnrollment(
          courseId: courseId,
          userId: user.uid,
          useCourseAlias: false,
          aliasDisplayName: null,
          aliasAvatarColorName: null,
          updatedByUserId: user.uid,
          updatedByRole: 'student',
        );
      } catch (_) {
        if (showBlockedMessage && context.mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              const SnackBar(
                content: Text('受講情報の初期化に失敗しました。時間をおいてもう一度お試しください。'),
              ),
            );
        }
        return false;
      }
      return true;
    }

    if (!context.mounted) {
      return false;
    }
    final setupResult = await Navigator.of(context)
        .push<_CourseAliasSetupResult>(
          MaterialPageRoute(
            builder: (_) => CourseAliasSetupPage(course: course),
          ),
        );
    if (setupResult == null) {
      if (showBlockedMessage && context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('受講開始をキャンセルしました。')));
      }
      return false;
    }
    try {
      final createdIdentity = await _courseEntryIdentityService
          .ensureIdentityAtEnrollment(
            courseId: courseId,
            userId: user.uid,
            useCourseAlias: setupResult.useAlias,
            aliasDisplayName: setupResult.aliasDisplayName,
            aliasAvatarColorName: setupResult.aliasAvatarColorName,
            updatedByUserId: user.uid,
            updatedByRole: 'student',
          );
      if (createdIdentity.isAliasMode) {
        await _courseEntryIdentityService.rewriteCourseAuthorSnapshots(
          courseId: courseId,
          userId: user.uid,
          snapshot: CourseAuthorSnapshot(
            displayName: createdIdentity.safeAliasDisplayName,
            avatarColorName: createdIdentity.safeAliasAvatarColorName,
            profileVisible: false,
            identityMode: courseIdentityModeAlias,
          ),
        );
      }
    } catch (_) {
      if (showBlockedMessage && context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Text('受講開始前の設定を保存できませんでした。時間をおいて再試行してください。'),
            ),
          );
      }
      return false;
    }
  }

  return true;
}

Future<bool> showCoursePolicyBlockDialog(
  BuildContext context, {
  required Course course,
  required String message,
}) async {
  if (!context.mounted) {
    return false;
  }
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return false;
  }
  final selection = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: const Text('同意が必要です'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('exit'),
            child: const Text('退出する'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('consent'),
            child: const Text('同意手続きへ'),
          ),
        ],
      );
    },
  );
  if (selection != 'consent') {
    return false;
  }
  if (!context.mounted) {
    return false;
  }
  return ensureCourseEntryAccess(context, course: course, user: user);
}

class CoursePrivacyConsentPage extends StatefulWidget {
  const CoursePrivacyConsentPage({
    super.key,
    required this.course,
    required this.requirement,
  });

  final Course course;
  final CourseEntryRequirement requirement;

  @override
  State<CoursePrivacyConsentPage> createState() =>
      _CoursePrivacyConsentPageState();
}

class _CoursePrivacyConsentPageState extends State<CoursePrivacyConsentPage> {
  late bool _agreeInstructorShare;
  late bool _agreePeerShare;
  late final TextEditingController _legalNameController;
  bool _isSaving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _agreeInstructorShare =
        widget.requirement.policy.shareWithInstructorEnabled;
    _agreePeerShare = widget.requirement.policy.shareAmongLearnersEnabled;
    _legalNameController = TextEditingController(
      text: widget.requirement.legalName ?? '',
    );
  }

  @override
  void dispose() {
    _legalNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _message = 'ログイン状態を確認できませんでした。';
        });
      }
      return;
    }
    if (widget.requirement.policy.shareWithInstructorEnabled &&
        !_agreeInstructorShare) {
      setState(() {
        _message = '先生への本名提供に同意しない場合は講座を開けません。';
      });
      return;
    }
    if (widget.requirement.policy.shareAmongLearnersEnabled &&
        !_agreePeerShare) {
      setState(() {
        _message = '受講者同士の本名公開に同意しない場合は講座を開けません。';
      });
      return;
    }
    if (widget.requirement.policy.requiresLegalName &&
        _legalNameController.text.trim().isEmpty) {
      setState(() {
        _message = 'この講座では本名の登録が必要です。';
      });
      return;
    }
    setState(() {
      _isSaving = true;
      _message = null;
    });
    try {
      await _courseEntryPrivacyService.saveConsent(
        userId: user.uid,
        courseId: widget.course.storageId,
        policy: widget.requirement.policy,
        agreeInstructorShare: _agreeInstructorShare,
        agreePeerShare: _agreePeerShare,
        legalName: _legalNameController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = widget.requirement.policy;
    return Scaffold(
      appBar: AppBar(title: const Text('本名情報の同意')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.course.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('この講座では、先生の設定に応じて本名情報の同意が必要です。同意しない場合は講座画面に入れません。'),
            const SizedBox(height: 16),
            if (policy.shareWithInstructorEnabled)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _agreeInstructorShare,
                onChanged: _isSaving
                    ? null
                    : (value) =>
                          setState(() => _agreeInstructorShare = value == true),
                title: const Text('先生に本名情報を提供することに同意する'),
              ),
            if (policy.shareAmongLearnersEnabled)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _agreePeerShare,
                onChanged: _isSaving
                    ? null
                    : (value) =>
                          setState(() => _agreePeerShare = value == true),
                title: const Text('受講者同士で本名を共有することに同意する'),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _legalNameController,
              enabled: !_isSaving && !widget.requirement.hasLegalName,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '本名（氏名）',
                helperText: '一度登録すると、本人では変更できません。',
              ),
            ),
            const SizedBox(height: 8),
            const Text('本名は、同意した範囲でのみ利用されます。受講者同士の表示では、プロフィール情報と結びつかない形で扱います。'),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _message!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ],
            if (_isSaving) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isSaving ? null : _submit,
              icon: const Icon(Icons.verified_user),
              label: const Text('同意して続ける'),
            ),
            TextButton(
              onPressed: _isSaving
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('今回は同意せず戻る'),
            ),
          ],
        ),
      ),
    );
  }
}

class CourseAliasSetupPage extends StatefulWidget {
  const CourseAliasSetupPage({super.key, required this.course});

  final Course course;

  @override
  State<CourseAliasSetupPage> createState() => _CourseAliasSetupPageState();
}

class _CourseAliasSetupPageState extends State<CourseAliasSetupPage> {
  bool _useAlias = false;
  String _aliasAvatarColorName = defaultProfileColorName;
  final TextEditingController _aliasController = TextEditingController();
  String? _message;

  @override
  void dispose() {
    _aliasController.dispose();
    super.dispose();
  }

  void _complete() {
    if (_useAlias && _aliasController.text.trim().isEmpty) {
      setState(() {
        _message = '講座専用の名前を入力してください。';
      });
      return;
    }
    Navigator.of(context).pop(
      _CourseAliasSetupResult(
        useAlias: _useAlias,
        aliasDisplayName: _useAlias ? _aliasController.text.trim() : null,
        aliasAvatarColorName: _useAlias ? _aliasAvatarColorName : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('受講開始の設定')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.course.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              '受講開始時に、この講座だけで使う名前とアイコン色を設定できます。設定しない場合はプロフィール情報が使われ、あとから講座専用表示に切り替えることはできません。',
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _useAlias,
              onChanged: (value) {
                setState(() {
                  _useAlias = value;
                  _message = null;
                });
              },
              title: const Text('この講座で講座専用の名前とアイコンを使う'),
            ),
            if (_useAlias) ...[
              TextField(
                controller: _aliasController,
                maxLength: 40,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '講座専用の名前',
                ),
              ),
              const SizedBox(height: 8),
              const Text('アイコン色'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in profileAvatarColors.entries)
                    ChoiceChip(
                      label: Text(entry.key),
                      selected: _aliasAvatarColorName == entry.key,
                      avatar: CircleAvatar(backgroundColor: entry.value),
                      onSelected: (_) {
                        setState(() {
                          _aliasAvatarColorName = entry.key;
                        });
                      },
                    ),
                ],
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _complete,
              icon: const Icon(Icons.play_arrow),
              label: const Text('この設定で受講開始'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseAliasSetupResult {
  const _CourseAliasSetupResult({
    required this.useAlias,
    this.aliasDisplayName,
    this.aliasAvatarColorName,
  });

  final bool useAlias;
  final String? aliasDisplayName;
  final String? aliasAvatarColorName;
}
