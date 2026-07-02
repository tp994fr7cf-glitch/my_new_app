import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/course_participant_identity.dart';
import '../models/course_privacy_policy.dart';
import '../models/lesson_note.dart';
import '../models/lesson_question.dart';
import '../models/course_profile_display.dart';
import '../models/public_user_profile.dart';
import '../services/course_identity_service.dart';
import '../services/course_privacy_service.dart';
import '../services/lesson_interaction_service.dart';
import 'public_user_profile_page.dart';
import 'shared/teacher_learner_restriction_dialog.dart';

class TeacherInteractionManagePage extends StatelessWidget {
  const TeacherInteractionManagePage({super.key, required this.course});

  final Course course;
  static const _lessonInteractionService = LessonInteractionService();
  static const _coursePrivacyService = CoursePrivacyService();
  static const _courseIdentityService = CourseIdentityService();

  String get _courseId => course.storageId;

  Future<void> _setPlatformEnabled({
    required int lessonNumber,
    required bool notesEnabled,
    required bool questionsEnabled,
  }) async {
    if (Firebase.apps.isEmpty) {
      return;
    }
    await FirebaseFirestore.instance
        .collection('lessonInteractionSettings')
        .doc(
          _lessonInteractionService.settingDocumentId(
            courseId: _courseId,
            lessonNumber: lessonNumber,
          ),
        )
        .set({
          'courseId': _courseId,
          'lessonNumber': lessonNumber,
          'instructorId': course.instructorId,
          'lessonNotesPublicEnabled': notesEnabled,
          'lessonQuestionsPublicEnabled': questionsEnabled,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> _setPublicModeration({
    required String collectionPath,
    required String? documentId,
    required String moderationStatus,
  }) async {
    await _lessonInteractionService.setPublicModeration(
      collectionPath: collectionPath,
      documentId: documentId,
      moderationStatus: moderationStatus,
    );
  }

  Stream<List<LessonNote>> _publicNotesStream() {
    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }
    return FirebaseFirestore.instance
        .collection('publicLessonNotes')
        .where('courseId', isEqualTo: _courseId)
        .snapshots()
        .map((snapshot) {
          return sortLessonNotesByUpdatedAt(
            snapshot.docs
                .map(LessonNote.fromFirestore)
                .where((note) => !note.isDeleted)
                .toList(),
          );
        });
  }

  Stream<List<LessonQuestion>> _publicQuestionsStream() {
    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }
    return FirebaseFirestore.instance
        .collection('publicLessonQuestions')
        .where('courseId', isEqualTo: _courseId)
        .snapshots()
        .map((snapshot) {
          return sortLessonQuestionsByUpdatedAt(
            snapshot.docs
                .map(LessonQuestion.fromFirestore)
                .where((question) => !question.isDeleted)
                .toList(),
          );
        });
  }

  Stream<Map<int, _LessonInteractionSetting>> _settingsStream() {
    if (Firebase.apps.isEmpty) {
      return Stream.value(const {});
    }
    return FirebaseFirestore.instance
        .collection('lessonInteractionSettings')
        .where('courseId', isEqualTo: _courseId)
        .snapshots()
        .map((snapshot) {
          return {
            for (final doc in snapshot.docs)
              (doc.data()['lessonNumber'] as num?)?.toInt() ?? 1:
                  _LessonInteractionSetting.fromMap(doc.data()),
          };
        });
  }

  Stream<CoursePrivacyPolicy> _privacyPolicyStream() {
    return _coursePrivacyService.policyStream(_courseId);
  }

  Future<void> _setPrivacyPolicy({
    required bool shareWithInstructorEnabled,
    required bool shareAmongLearnersEnabled,
  }) async {
    await _coursePrivacyService.updatePolicy(
      courseId: _courseId,
      shareWithInstructorEnabled: shareWithInstructorEnabled,
      shareAmongLearnersEnabled: shareAmongLearnersEnabled,
    );
  }

  Stream<List<CourseParticipantIdentity>> _participantIdentityStream() {
    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }
    return FirebaseFirestore.instance
        .collection('courses')
        .doc(_courseId)
        .collection('participantIdentities')
        .snapshots()
        .map((snapshot) {
          final identities = snapshot.docs
              .map(CourseParticipantIdentity.fromFirestore)
              .toList();
          identities.sort((a, b) {
            final aAt = a.updatedAt;
            final bAt = b.updatedAt;
            if (aAt != null && bAt != null) {
              return bAt.compareTo(aAt);
            }
            return a.userId.compareTo(b.userId);
          });
          return identities;
        });
  }

  Stream<List<Map<String, String>>> _teacherLegalNameSharesStream() {
    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }
    return FirebaseFirestore.instance
        .collection('courses')
        .doc(_courseId)
        .collection('teacherLegalNameShares')
        .snapshots()
        .map((snapshot) {
          final rows = snapshot.docs
              .map((doc) {
                final data = doc.data();
                final legalName = (data['legalName'] as String?)?.trim() ?? '';
                if (legalName.isEmpty) {
                  return null;
                }
                final userId = (data['userId'] as String?)?.trim();
                return {
                  'userId': (userId == null || userId.isEmpty)
                      ? doc.id
                      : userId,
                  'legalName': legalName,
                };
              })
              .whereType<Map<String, String>>()
              .toList();
          rows.sort((a, b) => (a['userId'] ?? '').compareTo(b['userId'] ?? ''));
          return rows;
        });
  }

  Stream<Map<String, String>> _teacherLegalNameShareMapStream() {
    return _teacherLegalNameSharesStream().map((rows) {
      return {
        for (final row in rows)
          if ((row['userId'] ?? '').isNotEmpty &&
              (row['legalName'] ?? '').isNotEmpty)
            row['userId']!: row['legalName']!,
      };
    });
  }

  Future<CourseParticipantIdentity> _loadParticipantIdentity(
    String learnerId,
  ) async {
    if (Firebase.apps.isEmpty || learnerId.trim().isEmpty) {
      return CourseParticipantIdentity(
        courseId: _courseId,
        userId: learnerId.trim(),
        identityMode: courseIdentityModeProfile,
        aliasConfiguredAtEnrollment: false,
        aliasRetired: false,
      );
    }
    final doc = await FirebaseFirestore.instance
        .collection('courses')
        .doc(_courseId)
        .collection('participantIdentities')
        .doc(learnerId.trim())
        .get();
    if (doc.exists) {
      return CourseParticipantIdentity.fromFirestore(doc);
    }
    return CourseParticipantIdentity(
      courseId: _courseId,
      userId: learnerId.trim(),
      identityMode: courseIdentityModeProfile,
      aliasConfiguredAtEnrollment: false,
      aliasRetired: false,
    );
  }

  Future<void> _openRestrictionDialogForAuthor({
    required BuildContext context,
    required String learnerId,
    required int lessonNumber,
  }) async {
    final identity = await _loadParticipantIdentity(learnerId);
    if (!context.mounted) {
      return;
    }
    await _openLearnerRestrictionDialog(
      context,
      identity: identity,
      initialLessonNumber: lessonNumber,
    );
  }

  Future<void> _showAliasProfileLockedDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('講座専用プロフィールを表示中です'),
          content: const Text('この受講者は講座専用プロフィールを使っているため、通常プロフィールには移動できません。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _forceUpdateAlias(
    BuildContext context,
    CourseParticipantIdentity identity,
  ) async {
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('対象ユーザー: ${identity.userId}'),
                    const SizedBox(height: 12),
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
                    const Text('アイコン色'),
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
                  child: const Text('変更する'),
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
    final teacherUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final safeName = draftDisplayName.trim();
    if (safeName.isEmpty || teacherUserId.isEmpty) {
      messenger
        ?..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('変更内容が不正のため保存できませんでした。')));
      return;
    }
    try {
      await _courseIdentityService.updateAlias(
        courseId: _courseId,
        userId: identity.userId,
        aliasDisplayName: safeName,
        aliasAvatarColorName: selectedColor,
        updatedByUserId: teacherUserId,
        updatedByRole: 'teacher',
        force: true,
      );
    } catch (_) {
      messenger
        ?..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('講座専用プロフィールの変更保存に失敗しました。')),
        );
      return;
    }
    try {
      await _courseIdentityService.rewriteCourseAuthorSnapshots(
        courseId: _courseId,
        userId: identity.userId,
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

  List<int> get _sortedLessonNumbers => sortedCourseLessonNumbers(course);

  Stream<Map<String, Map<int, String>>> _learnerRestrictionsSummaryStream() {
    if (Firebase.apps.isEmpty || _sortedLessonNumbers.isEmpty) {
      return Stream.value(const {});
    }
    return Stream.multi((controller) {
      final store = <String, Map<int, String>>{};
      final subscriptions = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

      void emitSummary() {
        controller.add({
          for (final entry in store.entries)
            entry.key: Map<int, String>.from(entry.value),
        });
      }

      for (final lessonNumber in _sortedLessonNumbers) {
        final settingId = _lessonInteractionService.settingDocumentId(
          courseId: _courseId,
          lessonNumber: lessonNumber,
        );
        final subscription = FirebaseFirestore.instance
            .collection('lessonInteractionSettings')
            .doc(settingId)
            .collection(
              LessonInteractionService.learnerRestrictionsCollectionName,
            )
            .snapshots()
            .listen((snapshot) {
              for (final learnerId in store.keys.toList()) {
                store[learnerId]?.remove(lessonNumber);
                if (store[learnerId]?.isEmpty ?? false) {
                  store.remove(learnerId);
                }
              }
              for (final doc in snapshot.docs) {
                store.putIfAbsent(doc.id, () => <int, String>{});
                store[doc.id]![lessonNumber] =
                    _lessonInteractionService.normalizeLearnerRestrictionMode(
                      doc.data()[
                          LessonInteractionService.learnerRestrictionModeField]
                          as String?,
                    );
              }
              emitSummary();
            }, onError: controller.addError);
        subscriptions.add(subscription);
      }

      controller.onCancel = () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      };
    });
  }

  Future<void> _openLearnerRestrictionDialog(
    BuildContext context, {
    required CourseParticipantIdentity identity,
    required int initialLessonNumber,
  }) async {
    final user = Firebase.apps.isEmpty
        ? null
        : FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await TeacherLearnerRestrictionDialog.show(
      context: context,
      course: course,
      courseId: _courseId,
      identity: identity,
      initialLessonNumber: initialLessonNumber,
      service: _lessonInteractionService,
    );
    if (result == null) {
      return;
    }
    try {
      final outcome = await _lessonInteractionService
          .applyLearnerRestrictionToLessons(
            courseId: _courseId,
            learnerId: identity.userId,
            lessonNumbers: result.targetLessonNumbers,
            restrictionMode: result.selectedMode,
            updatedByUserId: user.uid,
            bulkHide: result.bulkHide,
            bulkUnhide: result.bulkUnhide,
            unhidePolicy: result.bulkUnhidePolicy,
          );
      if (outcome.isFullSuccess) {
        final message = outcome.affectedPosts > 0
            ? '設定を保存しました。${result.targetLessonNumbers.length}レッスン分、公開状態を更新した投稿: ${outcome.affectedPosts}件'
            : '設定を保存しました。${result.targetLessonNumbers.length}レッスン分を更新しました。';
        messenger
          ?..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      final failedLabel = outcome.failedLessonNumbers.join(', ');
      final message = outcome.successLessonNumbers.isEmpty
          ? '設定の保存に失敗しました。'
          : '一部のレッスンで保存に失敗しました（レッスン: $failedLabel）。成功: ${outcome.successLessonNumbers.length}件';
      messenger
        ?..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    } on FirebaseException catch (error) {
      messenger
        ?..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(error.message ?? '設定の保存に失敗しました。')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('本名同意・公開投稿の管理')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              course.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('この画面で「本名同意設定（A/B）」と、公開メモ・公開質問の管理をまとめて行えます。'),
            const SizedBox(height: 24),
            StreamBuilder<CoursePrivacyPolicy>(
              stream: _privacyPolicyStream(),
              builder: (context, snapshot) {
                final policy = snapshot.data ?? CoursePrivacyPolicy.empty;
                return _CoursePrivacyPolicyCard(
                  policy: policy,
                  onChanged: _setPrivacyPolicy,
                );
              },
            ),
            const SizedBox(height: 24),
            StreamBuilder<Map<int, _LessonInteractionSetting>>(
              stream: _settingsStream(),
              builder: (context, snapshot) {
                final settings = snapshot.data ?? const {};
                return Column(
                  children: [
                    for (final entry in course.lessons.indexed)
                      _LessonSettingCard(
                        lessonNumber: entry.$1 + 1,
                        lesson: entry.$2,
                        setting: settings[entry.$1 + 1],
                        onChanged: _setPlatformEnabled,
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              '受講者ごとの設定',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '受講者ごとに、公開欄の閲覧・投稿を制限できます。講座専用表示を使っている受講者は、設定の下から強制変更もできます。',
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<CourseParticipantIdentity>>(
              stream: _participantIdentityStream(),
              builder: (context, identitySnapshot) {
                final identities =
                    identitySnapshot.data ??
                    const <CourseParticipantIdentity>[];
                if (identities.isEmpty) {
                  return const Text('制限対象の受講者はまだいません。');
                }
                return StreamBuilder<Map<String, String>>(
                  stream: _teacherLegalNameShareMapStream(),
                  builder: (context, legalNameSnapshot) {
                    final legalNames =
                        legalNameSnapshot.data ?? const <String, String>{};
                    return StreamBuilder<Map<String, Map<int, String>>>(
                      stream: _learnerRestrictionsSummaryStream(),
                      builder: (context, restrictionSnapshot) {
                        final restrictionsByLearner =
                            restrictionSnapshot.data ??
                            const <String, Map<int, String>>{};
                        return Column(
                          children: [
                            for (final identity in identities)
                              Card(
                                child: _LearnerRestrictionTile(
                                  courseId: _courseId,
                                  identity: identity,
                                  legalName: legalNames[identity.userId],
                                  restrictionLabel: _lessonInteractionService
                                      .summarizeRestrictionModesForLessons(
                                        modesByLesson:
                                            restrictionsByLearner[identity
                                                .userId] ??
                                            const {},
                                        lessonNumbers: _sortedLessonNumbers,
                                      ),
                                  onTapProfile: () {
                                    if (identity.isAliasMode) {
                                      _showAliasProfileLockedDialog(context);
                                      return;
                                    }
                                    showPublicUserProfilePreview(
                                      context: context,
                                      userId: identity.userId,
                                      role: publicUserProfileRoleStudent,
                                      fallbackDisplayName: '学習者',
                                      isOwner: false,
                                      courseId: _courseId,
                                    );
                                  },
                                  onOpenSettings: () =>
                                      _openLearnerRestrictionDialog(
                                        context,
                                        identity: identity,
                                        initialLessonNumber:
                                            youngestCourseLessonNumber(course),
                                      ),
                                  onForceUpdateAlias: identity.canEditAlias
                                      ? () =>
                                            _forceUpdateAlias(context, identity)
                                      : null,
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              '公開メモ',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<LessonNote>>(
              stream: _publicNotesStream(),
              builder: (context, snapshot) {
                final notes = snapshot.data ?? const <LessonNote>[];
                if (notes.isEmpty) {
                  return const Text('公開メモはまだありません。');
                }
                return Column(
                  children: [
                    for (final note in notes)
                      _PublicNoteCard(
                        note: note,
                        onTap: () => _showNoteDetails(context, note),
                        onToggleModeration: () => _setPublicModeration(
                          collectionPath: 'publicLessonNotes',
                          documentId: note.id,
                          moderationStatus: note.isTeacherHidden
                              ? lessonNoteModerationVisible
                              : lessonNoteModerationHiddenByTeacher,
                        ),
                        isInstructorAuthor:
                            note.authorId == course.instructorId,
                        onOpenRestrictionSettings:
                            note.authorId == course.instructorId
                            ? null
                            : () => _openRestrictionDialogForAuthor(
                                context: context,
                                learnerId: note.authorId,
                                lessonNumber: note.lessonNumber,
                              ),
                        onAliasProfileTap: () =>
                            _showAliasProfileLockedDialog(context),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              '公開質問',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<LessonQuestion>>(
              stream: _publicQuestionsStream(),
              builder: (context, snapshot) {
                final questions = snapshot.data ?? const <LessonQuestion>[];
                if (questions.isEmpty) {
                  return const Text('公開質問はまだありません。');
                }
                return Column(
                  children: [
                    for (final question in questions)
                      _PublicQuestionCard(
                        question: question,
                        onTap: () => _showQuestionDetails(context, question),
                        onToggleModeration: () => _setPublicModeration(
                          collectionPath: 'publicLessonQuestions',
                          documentId: question.id,
                          moderationStatus: question.isTeacherHidden
                              ? lessonNoteModerationVisible
                              : lessonNoteModerationHiddenByTeacher,
                        ),
                        isInstructorAuthor:
                            question.authorId == course.instructorId ||
                            question.authorRole == publicUserProfileRoleTeacher,
                        onOpenRestrictionSettings:
                            question.authorId == course.instructorId ||
                                question.authorRole ==
                                    publicUserProfileRoleTeacher
                            ? null
                            : () => _openRestrictionDialogForAuthor(
                                context: context,
                                learnerId: question.authorId,
                                lessonNumber: question.lessonNumber,
                              ),
                        onAliasProfileTap: () =>
                            _showAliasProfileLockedDialog(context),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showNoteDetails(BuildContext context, LessonNote note) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(_noteTitle(note)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _DetailRow(label: '投稿者', value: _authorName(note.authorName)),
                _DetailRow(
                  label: 'レッスン',
                  value: 'レッスン${note.lessonNumber}: ${note.lessonTitle}',
                ),
                _DetailRow(label: '状態', value: _statusText(note)),
                const SizedBox(height: 16),
                _DetailSection(
                  title: '本文',
                  body: note.body.isEmpty ? '本文はありません。' : note.body,
                ),
                if (note.tags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _DetailSection(title: 'タグ', body: note.tags.join(' / ')),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showQuestionDetails(
    BuildContext context,
    LessonQuestion question,
  ) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(_questionHeadline(question)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _DetailRow(
                  label: '投稿者',
                  value: _authorName(question.authorName),
                ),
                _DetailRow(
                  label: 'レッスン',
                  value:
                      'レッスン${question.lessonNumber}: ${question.lessonTitle}',
                ),
                _DetailRow(label: '状態', value: _statusText(question)),
                const SizedBox(height: 16),
                _DetailSection(
                  title: '質問本文',
                  body: question.body.isEmpty ? '本文はありません。' : question.body,
                ),
                if (hasQuotedNoteAttachment(
                  quotedNoteId: question.quotedNoteId,
                  quotedNoteTitle: question.quotedNoteTitle,
                  quotedNoteBody: question.quotedNoteBody,
                )) ...[
                  const SizedBox(height: 16),
                  _DetailSection(
                    title: '引用メモ',
                    body: [
                      quotedNoteDisplayTitle(
                        quotedNoteId: question.quotedNoteId,
                        quotedNoteTitle: question.quotedNoteTitle,
                      ),
                      if ((question.quotedNoteBody ?? '').trim().isNotEmpty)
                        question.quotedNoteBody!.trim(),
                    ].where((part) => part.isNotEmpty).join('\n'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }
}

class _PublicNoteCard extends StatelessWidget {
  const _PublicNoteCard({
    required this.note,
    required this.onTap,
    required this.onToggleModeration,
    required this.isInstructorAuthor,
    required this.onAliasProfileTap,
    this.onOpenRestrictionSettings,
  });

  final LessonNote note;
  final VoidCallback onTap;
  final VoidCallback onToggleModeration;
  final bool isInstructorAuthor;
  final VoidCallback onAliasProfileTap;
  final VoidCallback? onOpenRestrictionSettings;

  @override
  Widget build(BuildContext context) {
    final isAliasAuthor = note.authorIdentityMode == courseIdentityModeAlias;
    final fallbackProfile = _fallbackProfileWithColor(
      userId: note.authorId,
      role: isInstructorAuthor
          ? publicUserProfileRoleTeacher
          : publicUserProfileRoleStudent,
      displayName: _authorName(note.authorName),
      avatarColorName: note.authorAvatarColorName,
    );
    final profileRole = isInstructorAuthor
        ? publicUserProfileRoleTeacher
        : publicUserProfileRoleStudent;
    final profileStream = isAliasAuthor
        ? null
        : authorPublicProfileStream(
            courseId: note.courseId,
            authorId: note.authorId,
            authorRole: profileRole,
            authorProfileVisible: note.authorProfileVisible,
            fallbackDisplayName: fallbackProfile.displayName,
          );
    return StreamBuilder<PublicUserProfile>(
      stream: profileStream,
      initialData: fallbackProfile,
      builder: (context, snapshot) {
        final profile = snapshot.data ?? fallbackProfile;
        return Card(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      if (isAliasAuthor) {
                        onAliasProfileTap();
                        return;
                      }
                      showPublicUserProfilePreview(
                        context: context,
                        userId: note.authorId,
                        role: profileRole,
                        fallbackDisplayName: profile.displayName,
                        isOwner: false,
                        courseId: note.courseId,
                        authorProfileVisible: note.authorProfileVisible,
                      );
                    },
                    child: PublicProfileAvatar(profile: profile),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.displayName,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text('レッスン${note.lessonNumber}: ${note.lessonTitle}'),
                        const SizedBox(height: 8),
                        Text(_noteTitle(note)),
                        if (note.body.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(_previewText(note.body)),
                        ],
                        const SizedBox(height: 8),
                        _StatusWrap(labels: _statusLabels(note)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: onToggleModeration,
                        child: Text(note.isTeacherHidden ? '公開化' : '非公開化'),
                      ),
                      if (onOpenRestrictionSettings != null)
                        TextButton(
                          onPressed: onOpenRestrictionSettings,
                          child: const Text('非公開詳細設定'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PublicQuestionCard extends StatelessWidget {
  const _PublicQuestionCard({
    required this.question,
    required this.onTap,
    required this.onToggleModeration,
    required this.isInstructorAuthor,
    required this.onAliasProfileTap,
    this.onOpenRestrictionSettings,
  });

  final LessonQuestion question;
  final VoidCallback onTap;
  final VoidCallback onToggleModeration;
  final bool isInstructorAuthor;
  final VoidCallback onAliasProfileTap;
  final VoidCallback? onOpenRestrictionSettings;

  @override
  Widget build(BuildContext context) {
    final isAliasAuthor =
        question.authorIdentityMode == courseIdentityModeAlias;
    final fallbackProfile = _fallbackProfileWithColor(
      userId: question.authorId,
      role: isInstructorAuthor
          ? publicUserProfileRoleTeacher
          : publicUserProfileRoleStudent,
      displayName: _authorName(question.authorName),
      avatarColorName: question.authorAvatarColorName,
    );
    final profileRole = isInstructorAuthor
        ? publicUserProfileRoleTeacher
        : publicUserProfileRoleStudent;
    final profileStream = isAliasAuthor
        ? null
        : authorPublicProfileStream(
            courseId: question.courseId,
            authorId: question.authorId,
            authorRole: profileRole,
            authorProfileVisible: question.authorProfileVisible,
            fallbackDisplayName: fallbackProfile.displayName,
          );
    return StreamBuilder<PublicUserProfile>(
      stream: profileStream,
      initialData: fallbackProfile,
      builder: (context, snapshot) {
        final profile = snapshot.data ?? fallbackProfile;
        return Card(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      if (isAliasAuthor) {
                        onAliasProfileTap();
                        return;
                      }
                      showPublicUserProfilePreview(
                        context: context,
                        userId: question.authorId,
                        role: profileRole,
                        fallbackDisplayName: profile.displayName,
                        isOwner: false,
                        courseId: question.courseId,
                        authorProfileVisible: question.authorProfileVisible,
                      );
                    },
                    child: PublicProfileAvatar(profile: profile),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.displayName,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'レッスン${question.lessonNumber}: ${question.lessonTitle}',
                        ),
                        const SizedBox(height: 8),
                        Text(_questionHeadline(question)),
                        if (hasQuotedNoteAttachment(
                          quotedNoteId: question.quotedNoteId,
                          quotedNoteTitle: question.quotedNoteTitle,
                          quotedNoteBody: question.quotedNoteBody,
                        )) ...[
                          const SizedBox(height: 4),
                          Text(
                            '引用メモ: ${quotedNoteDisplayTitle(
                              quotedNoteId: question.quotedNoteId,
                              quotedNoteTitle: question.quotedNoteTitle,
                            )}',
                          ),
                        ],
                        const SizedBox(height: 8),
                        _StatusWrap(labels: _statusLabels(question)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: onToggleModeration,
                        child: Text(question.isTeacherHidden ? '公開化' : '非公開化'),
                      ),
                      if (onOpenRestrictionSettings != null)
                        TextButton(
                          onPressed: onOpenRestrictionSettings,
                          child: const Text('非公開詳細設定'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LearnerRestrictionTile extends StatelessWidget {
  const _LearnerRestrictionTile({
    required this.courseId,
    required this.identity,
    required this.restrictionLabel,
    required this.onTapProfile,
    required this.onOpenSettings,
    this.legalName,
    this.onForceUpdateAlias,
  });

  final String courseId;
  final CourseParticipantIdentity identity;
  final String restrictionLabel;
  final String? legalName;
  final VoidCallback onTapProfile;
  final VoidCallback onOpenSettings;
  final VoidCallback? onForceUpdateAlias;

  @override
  Widget build(BuildContext context) {
    final isAlias = identity.isAliasMode;
    final fallbackProfile = _fallbackProfileWithColor(
      userId: identity.userId,
      role: publicUserProfileRoleStudent,
      displayName: isAlias ? identity.safeAliasDisplayName : '学習者',
      avatarColorName: isAlias ? identity.safeAliasAvatarColorName : null,
    );
    final stream = isAlias
        ? null
        : courseSharedPublicProfileStream(
            courseId: courseId,
            userId: identity.userId,
            fallbackDisplayName: fallbackProfile.displayName,
          );
    return StreamBuilder<PublicUserProfile>(
      stream: stream,
      initialData: fallbackProfile,
      builder: (context, snapshot) {
        final profile = snapshot.data ?? fallbackProfile;
        final legalNameText = (legalName ?? '').trim();
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTapProfile,
            child: PublicProfileAvatar(profile: profile),
          ),
          title: Text(profile.displayName),
          subtitle: Text(
            [
              if (legalNameText.isNotEmpty) '本名: $legalNameText',
              restrictionLabel,
            ].join('\n'),
          ),
          isThreeLine: legalNameText.isNotEmpty,
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onOpenSettings,
                child: const Text('設定'),
              ),
              if (onForceUpdateAlias != null)
                TextButton(
                  onPressed: onForceUpdateAlias,
                  child: const Text('強制変更'),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusWrap extends StatelessWidget {
  const _StatusWrap({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final label in labels)
          Chip(
            label: Text(label),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('$label: $value'),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SelectableText(body),
      ],
    );
  }
}

String _noteTitle(LessonNote note) {
  final title = note.title.trim();
  return title.isEmpty ? '無題のメモ' : title;
}

String _questionHeadline(LessonQuestion question) {
  return _previewText(question.body, fallback: '本文のない質問');
}

String _previewText(
  String text, {
  String fallback = '本文はありません。',
  int maxLength = 80,
}) {
  final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) {
    return fallback;
  }
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return '${normalized.substring(0, maxLength)}...';
}

String _authorName(String authorName) {
  final trimmed = authorName.trim();
  return trimmed.isEmpty ? '投稿者不明' : trimmed;
}

PublicUserProfile _fallbackProfileWithColor({
  required String userId,
  required String role,
  required String displayName,
  String? avatarColorName,
}) {
  final fallback = fallbackPublicUserProfile(
    userId: userId,
    role: role,
    displayName: displayName,
  );
  final safeColor = (avatarColorName ?? '').trim();
  if (!profileAvatarColors.containsKey(safeColor)) {
    return fallback;
  }
  return PublicUserProfile(
    userId: fallback.userId,
    role: fallback.role,
    displayName: fallback.displayName,
    avatarColorName: safeColor,
    bio: fallback.bio,
    updatedAt: fallback.updatedAt,
  );
}

List<String> _statusLabels(Object item) {
  final isTeacherHidden = item is LessonNote
      ? item.isTeacherHidden
      : item is LessonQuestion
      ? item.isTeacherHidden
      : false;
  final isStudentPublic = item is LessonNote
      ? item.isStudentPublic
      : item is LessonQuestion
      ? item.isStudentPublic
      : true;

  return [
    if (isTeacherHidden) '先生が非公開化済み',
    if (!isTeacherHidden && isStudentPublic) '学習者にも公開中',
    if (!isStudentPublic) '先生だけ表示',
  ];
}

String _statusText(Object item) {
  return _statusLabels(item).join(' / ');
}

class _CoursePrivacyPolicyCard extends StatelessWidget {
  const _CoursePrivacyPolicyCard({
    required this.policy,
    required this.onChanged,
  });

  final CoursePrivacyPolicy policy;
  final Future<void> Function({
    required bool shareWithInstructorEnabled,
    required bool shareAmongLearnersEnabled,
  })
  onChanged;

  @override
  Widget build(BuildContext context) {
    final shareWithInstructor = policy.shareWithInstructorEnabled;
    final shareAmongLearners = policy.shareAmongLearnersEnabled;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '本名情報の講座設定',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('どちらの設定も任意です。受講者同士の本名公開を有効化する場合は、先生への本名提供も同時に有効化されます。'),
            const SizedBox(height: 8),
            Text('現在の同意バージョン: ${policy.consentPolicyVersion}'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('先生が受講者の本名情報を受け取る'),
              value: shareWithInstructor,
              onChanged: (value) {
                onChanged(
                  shareWithInstructorEnabled: value,
                  shareAmongLearnersEnabled: value ? shareAmongLearners : false,
                ).catchError((_) {});
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('受講者同士で本名を公開する'),
              value: shareAmongLearners,
              onChanged: (value) {
                onChanged(
                  shareWithInstructorEnabled: value
                      ? true
                      : shareWithInstructor,
                  shareAmongLearnersEnabled: value,
                ).catchError((_) {});
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LessonSettingCard extends StatelessWidget {
  const _LessonSettingCard({
    required this.lessonNumber,
    required this.lesson,
    required this.setting,
    required this.onChanged,
  });

  final int lessonNumber;
  final CourseLesson lesson;
  final _LessonInteractionSetting? setting;
  final Future<void> Function({
    required int lessonNumber,
    required bool notesEnabled,
    required bool questionsEnabled,
  })
  onChanged;

  @override
  Widget build(BuildContext context) {
    final notesEnabled = setting?.notesEnabled ?? true;
    final questionsEnabled = setting?.questionsEnabled ?? true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'レッスン$lessonNumber: ${lesson.title}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('公開メモ欄を公開する'),
              value: notesEnabled,
              onChanged: (value) {
                onChanged(
                  lessonNumber: lessonNumber,
                  notesEnabled: value,
                  questionsEnabled: questionsEnabled,
                );
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('公開質問欄を公開する'),
              value: questionsEnabled,
              onChanged: (value) {
                onChanged(
                  lessonNumber: lessonNumber,
                  notesEnabled: notesEnabled,
                  questionsEnabled: value,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LessonInteractionSetting {
  const _LessonInteractionSetting({
    required this.notesEnabled,
    required this.questionsEnabled,
  });

  final bool notesEnabled;
  final bool questionsEnabled;

  factory _LessonInteractionSetting.fromMap(Map<String, dynamic> data) {
    return _LessonInteractionSetting(
      notesEnabled: data['lessonNotesPublicEnabled'] != false,
      questionsEnabled: data['lessonQuestionsPublicEnabled'] != false,
    );
  }
}
